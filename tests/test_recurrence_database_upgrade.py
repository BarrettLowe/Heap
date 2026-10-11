from __future__ import annotations

import sqlite3
from datetime import datetime
from pathlib import Path
from uuid import UUID

from fastapi.testclient import TestClient

from heap.interface.app import create_app
from heap.logic.task import TaskStatus
from heap.persistence.sqlite_project_store import SQLiteProjectStore
from heap.persistence.sqlite_task_store import SQLiteTaskStore


def test_pre_recurrence_database_upgrade_preserves_existing_data(
    tmp_path: Path,
) -> None:
    """Upgrade a pre-recurrence database without changing its existing records."""
    database = tmp_path / "legacy.sqlite"
    project_id = "00000000-0000-4000-8000-000000000001"
    inbox_id = "00000000-0000-4000-8000-000000000002"
    waiting_id = "00000000-0000-4000-8000-000000000003"
    prerequisite_id = "00000000-0000-4000-8000-000000000004"
    completed_id = "00000000-0000-4000-8000-000000000005"
    connection = sqlite3.connect(database)
    connection.executescript(
        """
        CREATE TABLE tasks (
            id TEXT PRIMARY KEY NOT NULL,
            title TEXT NOT NULL,
            status TEXT NOT NULL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            priority INTEGER,
            duration_minutes INTEGER,
            project_id TEXT,
            on_deck_since TEXT,
            completed_at TEXT,
            externally_blocked INTEGER NOT NULL DEFAULT 0
                CHECK (externally_blocked IN (0, 1)),
            due_date TEXT
        );
        CREATE TABLE projects (
            id TEXT PRIMARY KEY NOT NULL,
            name TEXT NOT NULL,
            description TEXT,
            status TEXT NOT NULL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            completed_at TEXT,
            icon TEXT,
            color TEXT
        );
        CREATE TABLE task_dependencies (
            task_id TEXT NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
            prerequisite_id TEXT NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
            PRIMARY KEY (task_id, prerequisite_id),
            CHECK (task_id != prerequisite_id)
        );
        """
    )
    created = "2024-01-01T08:00:00+00:00"
    updated = "2024-02-01T09:30:00+00:00"
    connection.execute(
        "INSERT INTO projects VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
        (
            project_id,
            "Garden",
            "Custom project description",
            "active",
            created,
            updated,
            None,
            "yard",
            "#2468AC",
        ),
    )
    connection.executemany(
        "INSERT INTO tasks VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
        [
            (inbox_id, "Unsorted capture", "inbox", created, updated, None, None, None, None, None, 0, None),
            (waiting_id, "Waiting for materials", "on_deck", created, updated, 2, 30, project_id, "2024-01-15T08:00:00+00:00", None, 1, "2024-03-01"),
            (prerequisite_id, "Order materials", "on_deck", created, updated, 1, 15, None, "2024-01-10T08:00:00+00:00", None, 0, None),
            (completed_id, "Previous project task", "completed", created, updated, 3, 60, project_id, "2024-01-05T08:00:00+00:00", "2024-02-01T09:30:00+00:00", 0, None),
        ],
    )
    connection.execute(
        "INSERT INTO task_dependencies VALUES (?, ?)", (waiting_id, prerequisite_id)
    )
    connection.commit()
    original_tasks = connection.execute("SELECT * FROM tasks ORDER BY id").fetchall()
    original_projects = connection.execute("SELECT * FROM projects ORDER BY id").fetchall()
    original_links = connection.execute(
        "SELECT * FROM task_dependencies ORDER BY task_id, prerequisite_id"
    ).fetchall()
    connection.close()

    with SQLiteTaskStore(database) as task_store, SQLiteProjectStore(database):
        upgraded_connection = sqlite3.connect(database)
        columns = {
            row[1] for row in upgraded_connection.execute("PRAGMA table_info(tasks)")
        }
        assert {"repeat", "successor_id", "successor_created_updated_at"} <= columns
        assert upgraded_connection.execute(
            "SELECT repeat, successor_id, successor_created_updated_at FROM tasks"
        ).fetchall() == [(None, None, None)] * len(original_tasks)
        assert task_store.get(UUID(waiting_id)).status is TaskStatus.ON_HEAP
        assert task_store.get(UUID(waiting_id)).repeat is None
        upgraded_connection.close()

    with TestClient(create_app(database)) as client:
        assert client.get("/healthz").json() == {"status": "ok"}
        assert {item["id"] for item in client.get("/api/v1/inbox").json()["items"]} == {
            inbox_id
        }
        assert {item["id"] for item in client.get("/api/v1/heap?local_date=2024-02-01").json()["items"]} == {
            waiting_id,
            prerequisite_id,
        }
        assert client.get(f"/api/v1/tasks/{waiting_id}").status_code == 200
        assert client.get(f"/api/v1/projects/{project_id}").json()["icon"] == "yard"
        assert {
            item["id"]
            for item in client.get(
                f"/api/v1/projects/{project_id}/tasks"
            ).json()["items"]
        } == {waiting_id, completed_id}

    with SQLiteTaskStore(database) as task_store, SQLiteProjectStore(database):
        reopened = sqlite3.connect(database)
        assert reopened.execute(
            """SELECT id, title, status, created_at, updated_at, priority,
                      duration_minutes, project_id, on_deck_since, completed_at,
                      externally_blocked, due_date FROM tasks ORDER BY id"""
        ).fetchall() == original_tasks
        assert reopened.execute("SELECT * FROM projects ORDER BY id").fetchall() == original_projects
        assert reopened.execute(
            "SELECT * FROM task_dependencies ORDER BY task_id, prerequisite_id"
        ).fetchall() == original_links
        assert reopened.execute("SELECT COUNT(*) FROM tasks").fetchone() == (
            len(original_tasks),
        )
        assert reopened.execute("SELECT COUNT(*) FROM tasks WHERE status = 'completed'").fetchone() == (1,)
        reopened.close()
        assert task_store.get(UUID(completed_id)).completed_at == datetime.fromisoformat(
            "2024-02-01T09:30:00+00:00"
        )
