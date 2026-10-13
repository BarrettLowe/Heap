from datetime import UTC, datetime
from pathlib import Path
from uuid import UUID

import pytest
from fastapi.testclient import TestClient

from heap.interface.app import create_app
from heap.logic import task_operator
from heap.logic.task_operator import TaskOperator
from heap.persistence.sqlite_task_store import SQLiteTaskStore


NOW = datetime(2026, 10, 3, tzinfo=UTC)


def client_for(database: Path) -> TestClient:
    """Create an API client backed by a temporary database."""
    return TestClient(create_app(database, []), raise_server_exceptions=False)


def test_repeat_is_required_nullable_and_strictly_validated(tmp_path: Path) -> None:
    """Validate repeat metadata on full requests and task representations."""
    with client_for(tmp_path / "heap.sqlite") as client:
        captured = client.post("/api/v1/tasks", json={"title": "Clean filter"}).json()
        path = f"/api/v1/tasks/{captured['id']}"
        detail = client.get(path).json()
        assert detail["repeat"] is None
        assert client.get("/api/v1/inbox").json()["items"][0]["repeat"] is None
        invalid_values = [
            {}, {"unit": "days"}, {"unit": "weeks", "interval": "1"},
            {"unit": "days", "interval": 1},
            {"unit": "days", "interval": 0},
            {"unit": "days", "interval": -1},
            {"unit": "days", "interval": 1.0},
            {"unit": "days", "interval": 1e0},
            {"unit": "days", "interval": True},
            *[
                {"unit": "days", "interval": interval}
                for interval in (
                    "", "0", "-1", "+1", " 1", "1 ", "01", "1e0", "1.0", "x"
                )
            ],
            {"unit": "days", "interval": "1", "extra": True},
        ]
        for invalid in invalid_values:
            body = {
                "title": detail["title"], "priority": None,
                "duration_minutes": None, "externally_blocked": False,
                "project_id": None, "due_date": None,
                "repeat": invalid, "expected_updated_at": detail["updated_at"],
            }
            response = client.put(path + "/organization", json=body)
            assert response.status_code == 422
            assert response.json()["error"]["code"] == "invalid_request"
        missing = {
            "title": detail["title"], "priority": None,
            "duration_minutes": None, "externally_blocked": False,
            "project_id": None, "due_date": None,
            "expected_updated_at": detail["updated_at"],
        }
        assert client.put(path + "/organization", json=missing).status_code == 422
        interval_text = str(10**79 + 123)
        project = client.post("/api/v1/projects", json={"name": "Maintenance"}).json()
        valid = {
            **missing, "priority": 2, "duration_minutes": 30,
            "project_id": project["id"],
            "repeat": {"unit": "months", "interval": interval_text},
        }
        saved = client.put(path + "/organization", json=valid)
        assert saved.status_code == 200
        assert saved.json()["repeat"] == valid["repeat"]
        assert client.get(path).json()["repeat"] == valid["repeat"]
        assert client.get(
            f"/api/v1/projects/{project['id']}/tasks"
        ).json()["items"][0]["repeat"] == valid["repeat"]
        heap_items = client.get(
            "/api/v1/heap", params={"local_date": "2026-10-05"}
        ).json()["items"]
        assert heap_items[0]["repeat"] == valid["repeat"]
        with SQLiteTaskStore(tmp_path / "heap.sqlite") as store:
            assert store.get(UUID(captured["id"])).repeat.interval == 10**79 + 123
        inbox_capture = client.post(
            "/api/v1/tasks", json={"title": "Inbox recurrence"}
        ).json()
        inbox_detail = client.get(f"/api/v1/tasks/{inbox_capture['id']}").json()
        inbox_saved = client.put(
            f"/api/v1/tasks/{inbox_capture['id']}/organization",
            json={
                "title": inbox_detail["title"], "priority": None,
                "duration_minutes": None, "externally_blocked": False,
                "project_id": None, "due_date": None,
                "repeat": {"unit": "days", "interval": "14"},
                "expected_updated_at": inbox_detail["updated_at"],
            },
        ).json()
        assert inbox_saved["repeat"] == {"unit": "days", "interval": "14"}
        assert client.get("/api/v1/inbox").json()["items"][0]["repeat"] == inbox_saved["repeat"]


@pytest.mark.parametrize(
    "value", [None, "2026-2-03", "2026-02-30", "2026-02-03T00:00:00Z", 20260203]
)
def test_completion_requires_canonical_local_date(
    tmp_path: Path, value: object
) -> None:
    """Reject absent, malformed, impossible, and non-string local dates."""
    with client_for(tmp_path / "heap.sqlite") as client:
        task = client.post("/api/v1/tasks", json={"title": "One-off"}).json()
        body = {
            "completed": True, "expected_updated_at": task["updated_at"],
            "local_date": value,
        }
        response = client.put(f"/api/v1/tasks/{task['id']}/completion", json=body)
        assert response.status_code == 422


def test_repeating_completion_returns_original_and_successor_appears_on_reload(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Return only completed history while persisting its local-date successor."""
    monkeypatch.setattr(task_operator, "current_time", lambda: NOW)
    database = tmp_path / "heap.sqlite"
    with client_for(database) as client:
        captured = client.post("/api/v1/tasks", json={"title": "Clean filter"}).json()
        path = f"/api/v1/tasks/{captured['id']}"
        detail = client.get(path).json()
        setup = {
            "title": detail["title"], "priority": 2, "duration_minutes": 30,
            "externally_blocked": True, "project_id": None, "due_date": "2026-10-01",
            "repeat": {"unit": "months", "interval": "1"},
            "expected_updated_at": detail["updated_at"],
        }
        saved = client.put(path + "/organization", json=setup).json()
        monkeypatch.setattr(
            task_operator,
            "current_time",
            lambda: datetime(2026, 10, 4, tzinfo=UTC),
        )
        response = client.put(
            path + "/completion",
            json={"completed": True, "expected_updated_at": saved["updated_at"],
                  "local_date": "2025-01-31"},
        )
        assert response.status_code == 200
        completed = response.json()
        assert completed["id"] == captured["id"]
        assert completed["status"] == "completed"
        assert completed["repeat"] == setup["repeat"]
        with SQLiteTaskStore(database) as store:
            successors = [task for task in store.list_on_heap() if task.id != UUID(captured["id"])]
            assert len(successors) == 1
            assert successors[0].due_date.isoformat() == "2025-02-28"
            assert successors[0].externally_blocked is False
            assert successors[0].repeat == store.get(UUID(captured["id"])).repeat
        assert client.get(path).json() == completed
        undone = client.put(
            path + "/completion",
            json={"completed": False, "expected_updated_at": completed["updated_at"],
                  "local_date": "2025-02-01"},
        )
        assert undone.status_code == 200
        assert undone.json()["status"] == "on_heap"
        with SQLiteTaskStore(database) as store:
            assert len(store.list_on_heap()) == 1


def test_guarded_undo_conflict_uses_specific_http_error_and_keeps_history(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Keep completed history when its edited successor prevents Undo."""
    database = tmp_path / "heap.sqlite"
    monkeypatch.setattr(task_operator, "current_time", lambda: NOW)
    with client_for(database) as client:
        captured = client.post("/api/v1/tasks", json={"title": "Clean filter"}).json()
        path = f"/api/v1/tasks/{captured['id']}"
        detail = client.get(path).json()
        saved = client.put(
            path + "/organization",
            json={
                "title": detail["title"], "priority": 2, "duration_minutes": 30,
                "externally_blocked": False, "project_id": None, "due_date": None,
                "repeat": {"unit": "days", "interval": "1"},
                "expected_updated_at": detail["updated_at"],
            },
        ).json()
        completed = client.put(
            path + "/completion",
            json={"completed": True, "expected_updated_at": saved["updated_at"],
                  "local_date": "2026-10-05"},
        ).json()
        with SQLiteTaskStore(database) as store:
            predecessor = store.get(UUID(captured["id"]))
            assert predecessor is not None and predecessor.successor_id is not None
            successor_id = predecessor.successor_id
            TaskOperator(store).set_title(successor_id, "Edited successor")
        rejected = client.put(
            path + "/completion",
            json={"completed": False, "expected_updated_at": completed["updated_at"],
                  "local_date": "2026-10-05"},
        )
        assert rejected.status_code == 409
        assert rejected.json()["error"]["code"] == "recurrence_undo_conflict"
        assert client.get(path).json() == completed
        with SQLiteTaskStore(database) as store:
            assert store.get(successor_id).title == "Edited successor"


def test_repeating_completion_uses_local_date_and_overflow_writes_nothing(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Reject an unrepresentable next date before changing either task."""
    monkeypatch.setattr(task_operator, "current_time", lambda: NOW)
    database = tmp_path / "heap.sqlite"
    with client_for(database) as client:
        captured = client.post("/api/v1/tasks", json={"title": "Clean filter"}).json()
        path = f"/api/v1/tasks/{captured['id']}"
        current = client.get(path).json()
        setup = {
            "title": current["title"], "priority": 2, "duration_minutes": 30,
            "externally_blocked": False, "project_id": None, "due_date": None,
            "repeat": {"unit": "days", "interval": "9" * 400},
            "expected_updated_at": current["updated_at"],
        }
        saved = client.put(path + "/organization", json=setup).json()
        assert saved["repeat"]["interval"] == "9" * 400
        response = client.put(
            path + "/completion",
            json={"completed": True, "expected_updated_at": saved["updated_at"],
                  "local_date": "9999-12-31"},
        )
        assert response.status_code == 422
        assert response.json()["error"]["fields"][0]["field"] == "repeat"
        assert client.get(path).json() == saved
        with SQLiteTaskStore(database) as store:
            stored = store.get(UUID(captured["id"]))
            assert stored is not None
            assert stored.repeat.interval_as_decimal() == "9" * 400
            assert store.list_on_heap() == [stored]


def test_repeating_inbox_completion_is_not_misreported_as_overflow(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Keep the existing non-Heap completion conflict for repeating Inbox work."""
    monkeypatch.setattr(task_operator, "current_time", lambda: NOW)
    with client_for(tmp_path / "heap.sqlite") as client:
        captured = client.post("/api/v1/tasks", json={"title": "Inbox repeat"}).json()
        path = f"/api/v1/tasks/{captured['id']}"
        detail = client.get(path).json()
        saved = client.put(
            path + "/organization",
            json={
                "title": detail["title"], "priority": None, "duration_minutes": None,
                "externally_blocked": False, "project_id": None, "due_date": None,
                "repeat": {"unit": "days", "interval": "1"},
                "expected_updated_at": detail["updated_at"],
            },
        ).json()
        response = client.put(
            path + "/completion",
            json={"completed": True, "expected_updated_at": saved["updated_at"],
                  "local_date": "2026-10-05"},
        )
        assert response.status_code == 409
        assert response.json()["error"]["code"] == "task_not_on_heap"
