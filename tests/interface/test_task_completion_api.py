from __future__ import annotations

from datetime import UTC, datetime
import sqlite3
from pathlib import Path
from uuid import UUID

import pytest
from fastapi.testclient import TestClient
from pytest import MonkeyPatch

from heap.interface.app import create_app
from heap.logic import task_operator
from heap.logic.task_operator import TaskOperator
from heap.persistence.sqlite_task_store import SQLiteTaskStore

NOW = datetime(2026, 10, 3, 12, 34, 56, 123456, tzinfo=UTC)
LATER = datetime(2026, 10, 4, 9, 0, 0, 123456, tzinfo=UTC)
UNDO = datetime(2026, 10, 5, 9, 0, 0, 123456, tzinfo=UTC)


def client_for(database: Path) -> TestClient:
    """Build an API client backed by a temporary SQLite database."""
    return TestClient(create_app(database, []), raise_server_exceptions=False)


def completion_body(updated_at: str, completed: bool) -> dict[str, object]:
    """Build a completion request using the task's comparison token."""
    return {"completed": completed, "expected_updated_at": updated_at}


def test_completion_and_undo_keep_task_history_and_unrelated_fields(
    tmp_path: Path, monkeypatch: MonkeyPatch
) -> None:
    """Completing then undoing restores Heap placement and preserves task data."""
    database = tmp_path / "heap.sqlite"
    monkeypatch.setattr(task_operator, "current_time", lambda: NOW)
    with client_for(database) as client:
        project = client.post("/api/v1/projects", json={"name": "Fence"}).json()
        captured = client.post("/api/v1/tasks", json={"title": "Repair fence"}).json()
        prerequisite = client.post(
            "/api/v1/tasks", json={"title": "Buy supplies"}
        ).json()
    with SQLiteTaskStore(database) as store:
        TaskOperator(store).add_dependency(
            UUID(captured["id"]), UUID(prerequisite["id"])
        )

    with client_for(database) as client:
        path = f"/api/v1/tasks/{captured['id']}"
        detail = client.get(path).json()
        organization = {
            "title": "Repair fence", "priority": 2, "duration_minutes": 30,
            "externally_blocked": True, "project_id": project["id"],
            "due_date": None,
            "expected_updated_at": detail["updated_at"],
        }
        heap_task = client.put(path + "/organization", json=organization).json()
        assert heap_task["status"] == "on_heap"
        heap_age = heap_task["on_heap_since"]

        monkeypatch.setattr(task_operator, "current_time", lambda: LATER)
        completed_response = client.put(
            path + "/completion", json=completion_body(heap_task["updated_at"], True)
        )
        assert completed_response.status_code == 200
        completed = completed_response.json()
        assert completed["status"] == "completed"
        assert completed["on_heap_since"] == heap_age
        assert completed["project_id"] == project["id"]
        assert completed["externally_blocked"] is True
        assert set(completed) == set(heap_task)
        assert "on_deck_since" not in completed
        with SQLiteTaskStore(database) as store:
            persisted = store.get(UUID(captured["id"]))
            assert persisted is not None
            assert persisted.completed_at == LATER
            assert persisted.updated_at == LATER

        monkeypatch.setattr(task_operator, "current_time", lambda: UNDO)
        undone_response = client.put(
            path + "/completion",
            json=completion_body(completed["updated_at"], False),
        )
        assert undone_response.status_code == 200
        undone = undone_response.json()
        assert undone["status"] == "on_heap"
        assert undone["on_heap_since"] == heap_age
        assert undone["updated_at"] != completed["updated_at"]
        assert undone["project_id"] == project["id"]
        assert undone["externally_blocked"] is True
        assert client.get(path).json() == undone
        with SQLiteTaskStore(database) as store:
            persisted = store.get(UUID(captured["id"]))
            assert persisted is not None
            assert persisted.completed_at is None
            assert persisted.on_heap_since.isoformat().replace("+00:00", "Z") == heap_age
    with SQLiteTaskStore(database) as store:
        assert TaskOperator(store).list_dependencies(UUID(captured["id"])) == [
            UUID(prerequisite["id"])
        ]


def test_completion_noop_requires_current_token_and_stale_token_conflicts(
    tmp_path: Path, monkeypatch: MonkeyPatch
) -> None:
    """Repeated desired state is a no-op, while old comparison tokens conflict."""
    monkeypatch.setattr(task_operator, "current_time", lambda: NOW)
    with client_for(tmp_path / "heap.sqlite") as client:
        captured = client.post("/api/v1/tasks", json={"title": "Repair fence"}).json()
        path = f"/api/v1/tasks/{captured['id']}"
        task = client.get(path).json()
        setup = {
            "title": task["title"], "priority": 2, "duration_minutes": 30,
            "externally_blocked": False, "project_id": None,
            "due_date": None,
            "expected_updated_at": task["updated_at"],
        }
        heap_task = client.put(path + "/organization", json=setup).json()
        monkeypatch.setattr(task_operator, "current_time", lambda: LATER)
        completed = client.put(
            path + "/completion", json=completion_body(heap_task["updated_at"], True)
        ).json()
        same = client.put(
            path + "/completion", json=completion_body(completed["updated_at"], True)
        )
        assert same.status_code == 200
        assert same.json() == completed
        stale = client.put(
            path + "/completion", json=completion_body(heap_task["updated_at"], False)
        )
        assert stale.status_code == 409
        assert stale.json()["error"]["code"] == "task_conflict"


@pytest.mark.parametrize(
    "body",
    [
        {"completed": 1, "expected_updated_at": "2026-10-03T12:34:56.123456Z"},
        {"completed": "true", "expected_updated_at": "2026-10-03T12:34:56.123456Z"},
        {"completed": True, "expected_updated_at": "2026-10-03T12:34:56Z"},
        {"completed": True, "expected_updated_at": "2026-10-03T12:34:56.123456Z", "extra": 1},
        {"expected_updated_at": "2026-10-03T12:34:56.123456Z"},
    ],
)
def test_completion_rejects_non_strict_or_extra_fields(tmp_path: Path, body: dict[str, object]) -> None:
    """Completion request requires exactly a strict bool and canonical token."""
    with client_for(tmp_path / "heap.sqlite") as client:
        captured = client.post("/api/v1/tasks", json={"title": "Repair fence"}).json()
        response = client.put(
            f"/api/v1/tasks/{captured['id']}/completion", json=body
        )
        assert response.status_code == 422
        assert response.json()["error"]["code"] == "invalid_request"


def test_completion_inbox_and_unqualified_undo_are_rejected(tmp_path: Path) -> None:
    """Inbox completion and undo without saved Heap history return 409."""
    with client_for(tmp_path / "heap.sqlite") as client:
        captured = client.post("/api/v1/tasks", json={"title": "Inbox task"}).json()
        path = f"/api/v1/tasks/{captured['id']}"
        inbox = client.get(path).json()
        completion = client.put(
            path + "/completion", json=completion_body(inbox["updated_at"], True)
        )
        assert completion.status_code == 409
        assert completion.json()["error"]["code"] == "task_not_on_heap"

    with SQLiteTaskStore(tmp_path / "heap.sqlite") as store:
        completed_task = TaskOperator(store).complete(UUID(captured["id"]))
    with client_for(tmp_path / "heap.sqlite") as client:
        response = client.put(
            f"/api/v1/tasks/{captured['id']}/completion",
            json=completion_body(
                completed_task.updated_at.isoformat().replace("+00:00", "Z"), False
            ),
        )
        assert response.status_code == 409
        assert response.json()["error"]["code"] == "task_not_on_heap"


def test_completion_storage_failure_returns_error_without_changing_task(
    tmp_path: Path, monkeypatch: MonkeyPatch
) -> None:
    """A failed atomic save does not return a successful completion response."""
    monkeypatch.setattr(task_operator, "current_time", lambda: NOW)
    database = tmp_path / "heap.sqlite"
    with client_for(database) as client:
        captured = client.post("/api/v1/tasks", json={"title": "Repair"}).json()
        path = f"/api/v1/tasks/{captured['id']}"
        task = client.get(path).json()
        setup = {
            "title": task["title"], "priority": 2, "duration_minutes": 30,
            "externally_blocked": False, "project_id": None,
            "due_date": None,
            "expected_updated_at": task["updated_at"],
        }
        heap_task = client.put(path + "/organization", json=setup).json()
        store = client.app.app.state.tasks._store

        def fail_save(value: object) -> None:
            """Raise as SQLite does when a transaction cannot be saved."""
            raise sqlite3.OperationalError("Write failed")

        monkeypatch.setattr(store, "save", fail_save)
        failed = client.put(
            path + "/completion",
            json=completion_body(heap_task["updated_at"], True),
        )
        assert failed.status_code == 500
        assert client.get(path).json() == heap_task


@pytest.mark.parametrize("completion_time", [LATER, NOW], ids=["equal", "backward"])
def test_completion_advances_token_despite_equal_or_backward_clock(
    tmp_path: Path, monkeypatch: MonkeyPatch, completion_time: datetime
) -> None:
    """Completion invalidates old tokens while retaining its actual clock time."""
    database = tmp_path / "heap.sqlite"
    monkeypatch.setattr(task_operator, "current_time", lambda: LATER)
    with client_for(database) as client:
        captured = client.post("/api/v1/tasks", json={"title": "Repair"}).json()
        path = f"/api/v1/tasks/{captured['id']}"
        heap_response = client.put(
            path + "/organization",
            json={
                "title": captured["title"],
                "priority": 2,
                "duration_minutes": 30,
                "externally_blocked": False,
                "project_id": None,
                "due_date": None,
                "expected_updated_at": captured["updated_at"],
            },
        )
        assert heap_response.status_code == 200
        heap_task = heap_response.json()
        monkeypatch.setattr(task_operator, "current_time", lambda: completion_time)
        response = client.put(
            path + "/completion", json=completion_body(heap_task["updated_at"], True)
        )
        assert response.status_code == 200
        completed = response.json()

        stale_undo = client.put(
            path + "/completion",
            json=completion_body(heap_task["updated_at"], False),
        )
        assert stale_undo.status_code == 409
        assert stale_undo.json()["error"]["code"] == "task_conflict"
        assert client.get(path).json() == completed
        assert completed["updated_at"] > heap_task["updated_at"]
        with SQLiteTaskStore(database) as store:
            persisted = store.get(UUID(captured["id"]))
            assert persisted is not None
            assert persisted.completed_at == completion_time
            assert persisted.updated_at > LATER

        repeated = client.put(
            path + "/completion", json=completion_body(completed["updated_at"], True)
        )
        assert repeated.status_code == 200
        assert repeated.json() == completed
        undo = client.put(
            path + "/completion", json=completion_body(completed["updated_at"], False)
        )
        assert undo.status_code == 200
        assert undo.json()["updated_at"] > completed["updated_at"]
        assert undo.json()["on_heap_since"] == heap_task["on_heap_since"]
