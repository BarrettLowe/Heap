from __future__ import annotations

import sqlite3
from datetime import UTC, datetime
from pathlib import Path

from fastapi.testclient import TestClient
from pytest import MonkeyPatch

from heap.interface.app import create_app
from heap.logic import task_operator
from heap.persistence.sqlite_task_store import SQLiteTaskStore

NOW = datetime(2026, 10, 3, 12, 0, tzinfo=UTC)
DATE = "2026-10-01"


def client_for(database: Path) -> TestClient:
    """Build an API client backed by a temporary database."""
    return TestClient(create_app(database, []), raise_server_exceptions=False)


def organization(task: dict[str, object], due_date: str | None) -> dict[str, object]:
    """Build a complete organization request using the current task token."""
    return {
        "title": task["title"],
        "priority": 2,
        "duration_minutes": 30,
        "externally_blocked": False,
        "project_id": None,
        "due_date": due_date,
        "expected_updated_at": task["updated_at"],
    }


def capture_and_organize(
    client: TestClient, due_date: str = DATE
) -> tuple[dict[str, object], str]:
    """Create a Heap task with a due date and return it with its detail path."""
    captured = client.post("/api/v1/tasks", json={"title": "Repair"}).json()
    path = f"/api/v1/tasks/{captured['id']}"
    response = client.put(path + "/organization", json=organization(captured, due_date))
    assert response.status_code == 200
    return response.json(), path


def test_due_only_noop_and_stale_date_edit_use_comparison_token(
    tmp_path: Path, monkeypatch: MonkeyPatch
) -> None:
    """Same-date saves retain the token; date-only edits invalidate old tokens."""
    monkeypatch.setattr(task_operator, "current_time", lambda: NOW)
    with client_for(tmp_path / "heap.sqlite") as client:
        task, path = capture_and_organize(client)
        unchanged = client.put(path + "/organization", json=organization(task, DATE)).json()
        assert unchanged["updated_at"] == task["updated_at"]
        changed = client.put(path + "/organization", json=organization(task, "2026-10-02"))
        assert changed.status_code == 200
        assert changed.json()["due_date"] == "2026-10-02"
        stale = client.put(path + "/organization", json=organization(task, "2026-10-04"))
        assert stale.status_code == 409
        assert stale.json()["error"]["code"] == "task_conflict"
        assert client.get(path).json()["due_date"] == "2026-10-02"


def test_failed_due_date_save_rolls_back_and_reopen_preserves_date(
    tmp_path: Path, monkeypatch: MonkeyPatch
) -> None:
    """A failed atomic save leaves the old date intact across API restart."""
    database = tmp_path / "heap.sqlite"
    monkeypatch.setattr(task_operator, "current_time", lambda: NOW)
    with client_for(database) as client:
        task, path = capture_and_organize(client)
        store = client.app.app.state.tasks._store

        def fail_save(value: object) -> None:
            """Simulate a SQLite write failure."""
            raise sqlite3.OperationalError("Write failed")

        monkeypatch.setattr(store, "save", fail_save)
        failed = client.put(
            path + "/organization", json=organization(task, "2026-10-02")
        )
        assert failed.status_code == 500
        assert client.get(path).json()["due_date"] == DATE
    with client_for(database) as client:
        assert client.get(path).json()["due_date"] == DATE


def test_due_date_is_null_in_bulk_and_project_task_responses(tmp_path: Path) -> None:
    """Undated capture has a required null due date in every expanded response."""
    with client_for(tmp_path / "heap.sqlite") as client:
        project = client.post("/api/v1/projects", json={"name": "Home"}).json()
        captured = client.post("/api/v1/tasks", json={"title": "Repair"}).json()
        inbox_task = client.get("/api/v1/inbox").json()["items"][0]
        assert inbox_task["due_date"] is None
        body = organization(captured, None)
        body["project_id"] = project["id"]
        organized = client.put(
            f"/api/v1/tasks/{captured['id']}/organization", json=body
        ).json()
        project_task = client.get(
            f"/api/v1/projects/{project['id']}/tasks"
        ).json()["items"][0]
        assert organized["due_date"] is None
        assert project_task["due_date"] is None
        assert client.get("/api/v1/tasks/" + captured["id"]).json()["due_date"] is None


def test_completion_and_undo_responses_retain_due_date(
    tmp_path: Path, monkeypatch: MonkeyPatch
) -> None:
    """Completion and undo serialize the stored date without shifting it."""
    monkeypatch.setattr(task_operator, "current_time", lambda: NOW)
    with client_for(tmp_path / "heap.sqlite") as client:
        task, path = capture_and_organize(client)
        completed = client.put(
            path + "/completion",
            json={"completed": True, "expected_updated_at": task["updated_at"]},
        )
        assert completed.status_code == 200
        completed_task = completed.json()
        assert completed_task["due_date"] == DATE
        undone = client.put(
            path + "/completion",
            json={
                "completed": False,
                "expected_updated_at": completed_task["updated_at"],
            },
        )
        assert undone.status_code == 200
        assert undone.json()["due_date"] == DATE
        assert client.get(path).json()["due_date"] == DATE
