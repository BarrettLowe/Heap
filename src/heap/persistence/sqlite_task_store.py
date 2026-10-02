from __future__ import annotations

import sqlite3
from datetime import datetime
from pathlib import Path
from types import TracebackType
from uuid import UUID

from heap.logic.duration import Duration
from heap.logic.priority import Priority
from heap.logic.task import Task, TaskStatus
from heap.logic.task_store import TaskStore


class SQLiteTaskStore(TaskStore):
    """Save and retrieve tasks using a SQLite connection."""

    def __init__(self, database: Path) -> None:
        """Open the database and create task storage if it does not exist."""
        self._connection = sqlite3.connect(database)
        self._connection.execute(
            """
            CREATE TABLE IF NOT EXISTS tasks (
                id TEXT PRIMARY KEY NOT NULL,
                title TEXT NOT NULL,
                status TEXT NOT NULL,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                priority INTEGER,
                duration_minutes INTEGER,
                project_id TEXT,
                on_deck_since TEXT
            )
            """
        )
        columns = {
            row[1] for row in self._connection.execute("PRAGMA table_info(tasks)")
        }
        for column, sql_type in (
            ("priority", "INTEGER"),
            ("duration_minutes", "INTEGER"),
            ("project_id", "TEXT"),
            ("on_deck_since", "TEXT"),
        ):
            if column not in columns:
                self._connection.execute(
                    f"ALTER TABLE tasks ADD COLUMN {column} {sql_type}"
                )
        self._connection.commit()

    def save(self, task: Task) -> None:
        """Write the task snapshot and commit it before returning."""
        with self._connection:
            self._connection.execute(
                """
                INSERT INTO tasks
                    (id, title, status, created_at, updated_at,
                     priority, duration_minutes, project_id, on_deck_since)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    title = excluded.title,
                    status = excluded.status,
                    created_at = excluded.created_at,
                    updated_at = excluded.updated_at,
                    priority = excluded.priority,
                    duration_minutes = excluded.duration_minutes,
                    project_id = excluded.project_id,
                    on_deck_since = excluded.on_deck_since
                """,
                (
                    str(task.id),
                    task.title,
                    task.status.value,
                    task.created_at.isoformat(),
                    task.updated_at.isoformat(),
                    task.priority.value if task.priority is not None else None,
                    task.duration.minutes,
                    str(task.project_id) if task.project_id is not None else None,
                    task.on_deck_since.isoformat() if task.on_deck_since else None,
                ),
            )

    def get(self, task_id: UUID) -> Task | None:
        """Load an independent task snapshot, or None for an absent ID."""
        row = self._connection.execute(
            """
            SELECT id, title, status, created_at, updated_at,
                   priority, duration_minutes, project_id, on_deck_since
            FROM tasks WHERE id = ?
            """,
            (str(task_id),),
        ).fetchone()
        if row is None:
            return None
        return self._task_from_row(row)

    def list_inbox(self) -> list[Task]:
        """Load inbox snapshots ordered by creation time, then ID."""
        rows = self._connection.execute(
            """
            SELECT id, title, status, created_at, updated_at,
                   priority, duration_minutes, project_id, on_deck_since
            FROM tasks
            WHERE status = ?
            ORDER BY created_at, id
            """,
            (TaskStatus.INBOX.value,),
        ).fetchall()
        return [self._task_from_row(row) for row in rows]

    @staticmethod
    def _task_from_row(
        row: tuple[
            str, str, str, str, str, int | None, int | None, str | None, str | None
        ],
    ) -> Task:
        """Convert a stored row into an independent task snapshot."""
        return Task(
            id=UUID(row[0]),
            title=row[1],
            status=TaskStatus(row[2]),
            created_at=datetime.fromisoformat(row[3]),
            updated_at=datetime.fromisoformat(row[4]),
            priority=Priority(row[5]) if row[5] is not None else None,
            duration=Duration(row[6]),
            project_id=UUID(row[7]) if row[7] is not None else None,
            on_deck_since=datetime.fromisoformat(row[8]) if row[8] else None,
        )

    def close(self) -> None:
        """Close the database connection."""
        self._connection.close()

    def __enter__(self) -> SQLiteTaskStore:
        """Return the open store for use in a with block."""
        return self

    def __exit__(
        self,
        exc_type: type[BaseException] | None,
        exc_value: BaseException | None,
        traceback: TracebackType | None,
    ) -> None:
        """Close the connection when leaving a with block."""
        self.close()
