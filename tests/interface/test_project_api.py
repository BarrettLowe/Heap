from __future__ import annotations

from datetime import UTC, datetime
from pathlib import Path
from uuid import UUID

from fastapi.testclient import TestClient
from pytest import MonkeyPatch

from heap.interface.app import create_app
from heap.logic import project_operator, task_operator
from heap.logic.task_operator import TaskOperator
from heap.persistence.sqlite_task_store import SQLiteTaskStore

CREATED = datetime(2026, 8, 1, 12, tzinfo=UTC)
EDITED = datetime(2026, 8, 2, 12, tzinfo=UTC)


def api_client(database: Path) -> TestClient:
    """Use an isolated SQLite database and contract error responses."""
    return TestClient(
        create_app(database, ["https://heap.example"]), raise_server_exceptions=False
    )


def test_project_crud_and_full_task_view_round_trip(
    tmp_path: Path,
    monkeypatch: MonkeyPatch,
) -> None:
    """Project API lists, creates, edits, and returns assigned tasks of every status."""
    database = tmp_path / "heap.sqlite"
    monkeypatch.setattr(project_operator, "current_time", lambda: CREATED)
    monkeypatch.setattr(task_operator, "current_time", lambda: CREATED)
    with api_client(database) as client:
        created = client.post(
            "/api/v1/projects", json={"name": "  Fence  ", "description": "Repair"}
        )
        assert created.status_code == 201
        project = created.json()
        assert project == {
            "id": project["id"],
            "name": "Fence",
            "description": "Repair",
            "status": "active",
            "created_at": "2026-08-01T12:00:00.000000Z",
            "updated_at": "2026-08-01T12:00:00.000000Z",
            "completed_at": None,
        }
        assert client.get("/api/v1/projects").json() == {"items": [project]}
        assert client.get(f"/api/v1/projects/{project['id']}").json() == project

        captured = client.post(
            "/api/v1/tasks", json={"title": "Repair the fence"}
        ).json()
        assert "project_id" not in captured
        monkeypatch.setattr(task_operator, "current_time", lambda: EDITED)
        saved = client.put(
            f"/api/v1/tasks/{captured['id']}/organization",
            json={
                "title": captured["title"],
                "priority": 2,
                "duration_minutes": 30,
                "externally_blocked": False,
                "project_id": project["id"],
                "expected_updated_at": captured["updated_at"],
            },
        )
        assert saved.status_code == 200
        task = saved.json()
        assert task["project_id"] == project["id"]
        assert task["status"] == "on_heap"
        assert client.get(f"/api/v1/projects/{project['id']}/tasks").json() == {
            "items": [task]
        }
        assert (
            client.get("/api/v1/heap").json()["items"][0]["project_id"] == project["id"]
        )
        assert client.get("/api/v1/inbox").json() == {"items": []}

        monkeypatch.setattr(project_operator, "current_time", lambda: EDITED)
        updated = client.put(
            f"/api/v1/projects/{project['id']}",
            json={"name": "Fence repair", "description": None},
        )
        assert updated.status_code == 200
        assert updated.json() == {
            **project,
            "name": "Fence repair",
            "description": None,
            "updated_at": "2026-08-02T12:00:00.000000Z",
        }
        assert client.get(f"/api/v1/projects/{project['id']}/tasks").json() == {
            "items": [task]
        }


def test_project_delete_removes_assigned_tasks_and_dependencies_atomically(
    tmp_path: Path,
    monkeypatch: MonkeyPatch,
) -> None:
    """Delete removes every task state, dependency links, and project in one action."""
    database = tmp_path / "heap.sqlite"
    monkeypatch.setattr(project_operator, "current_time", lambda: CREATED)
    monkeypatch.setattr(task_operator, "current_time", lambda: CREATED)
    with api_client(database) as client:
        first = client.post("/api/v1/projects", json={"name": "First"}).json()
        retained = client.post("/api/v1/projects", json={"name": "Retained"}).json()
        assigned = client.post("/api/v1/tasks", json={"title": "Assigned"}).json()
        dependent = client.post("/api/v1/tasks", json={"title": "Outside"}).json()
        for task_id, project_id in (
            (assigned["id"], first["id"]),
            (dependent["id"], retained["id"]),
        ):
            task = client.get(f"/api/v1/tasks/{task_id}").json()
            response = client.put(
                f"/api/v1/tasks/{task_id}/organization",
                json={
                    "title": task["title"],
                    "priority": None,
                    "duration_minutes": None,
                    "externally_blocked": False,
                    "project_id": project_id,
                    "expected_updated_at": task["updated_at"],
                },
            )
            assert response.status_code == 200
        assigned_detail = client.get(f"/api/v1/tasks/{assigned['id']}").json()
        # The link is created through storage to keep this endpoint test focused.
        with SQLiteTaskStore(database) as store:
            TaskOperator(store).add_dependency(
                UUID(dependent["id"]), UUID(assigned["id"])
            )
        outside_detail = client.get(f"/api/v1/tasks/{dependent['id']}").json()
        response = client.delete(
            f"/api/v1/projects/{first['id']}",
            headers={"Origin": "https://heap.example"},
        )
        assert response.status_code == 200
        assert response.json() == {"deleted": True}
        assert response.headers["access-control-allow-origin"] == "https://heap.example"
        assert client.get(f"/api/v1/projects/{first['id']}").status_code == 404
        assert client.get(f"/api/v1/tasks/{assigned['id']}").status_code == 404
        assert client.get(f"/api/v1/tasks/{dependent['id']}").json() == outside_detail
        assert client.get(f"/api/v1/projects/{retained['id']}/tasks").json() == {
            "items": [outside_detail]
        }
        assert assigned_detail["project_id"] == first["id"]
        deleted_again = client.delete(f"/api/v1/projects/{first['id']}")
        assert deleted_again.status_code == 404

    with SQLiteTaskStore(database) as store:
        assert store.list_dependencies(UUID(dependent["id"])) == []
        assert store.get(UUID(assigned["id"])) is None


def test_project_api_rejects_invalid_and_missing_requests_without_writes(
    tmp_path: Path,
    monkeypatch: MonkeyPatch,
) -> None:
    """Project endpoints validate IDs and strict bodies before changing storage."""
    database = tmp_path / "heap.sqlite"
    reads = 0

    def read_time() -> datetime:
        """Count project-operation time reads."""
        nonlocal reads
        reads += 1
        return CREATED

    monkeypatch.setattr(project_operator, "current_time", read_time)
    with api_client(database) as client:
        for body in ({}, {"name": " "}, {"name": 4}, {"name": "x", "other": True}):
            response = client.post("/api/v1/projects", json=body)
            assert response.status_code == 422
            assert response.json()["error"]["code"] == "invalid_request"
        assert (
            client.post("/api/v1/projects", json={"name": "Valid"}).status_code == 201
        )
        reads = 1
        before = client.get("/api/v1/projects").json()
        for project_id, expected in (
            ("--bad--", 422),
            ("00000000-0000-0000-0000-000000000001", 404),
        ):
            assert client.get(f"/api/v1/projects/{project_id}").status_code == expected
            response = client.delete(f"/api/v1/projects/{project_id}")
            assert response.status_code == expected
        invalid_update = client.put(
            "/api/v1/projects/00000000-0000-0000-0000-000000000001",
            json={"name": "Changed", "description": None},
        )
        assert invalid_update.status_code == 404
        assert client.get("/api/v1/projects").json() == before
        assert reads == 1


def test_delete_project_cors_preflight_allows_delete(tmp_path: Path) -> None:
    """Browser preflight permits the project deletion method."""
    with api_client(tmp_path / "heap.sqlite") as client:
        response = client.options(
            "/api/v1/projects/00000000-0000-0000-0000-000000000001",
            headers={
                "Origin": "https://heap.example",
                "Access-Control-Request-Method": "DELETE",
            },
        )
        assert response.status_code == 200
        assert "DELETE" in response.headers["access-control-allow-methods"]
