from __future__ import annotations

import json
import sqlite3
from datetime import date, datetime
from pathlib import Path
from types import TracebackType
from uuid import UUID

from heap.logic.duration import Duration
from heap.logic.priority import Priority
from heap.logic.recurrence import RepeatRule
from heap.logic.task import Task, TaskStatus
from heap.logic.task_store import TaskStore


class SQLiteTaskStore(TaskStore):
    """Save and retrieve tasks using a SQLite connection."""

    def __init__(self, database: Path) -> None:
        """Open the database and create task storage if it does not exist."""
        self._connection = sqlite3.connect(database)
        self._connection.execute("PRAGMA foreign_keys = ON")
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
                on_deck_since TEXT,
                completed_at TEXT,
                externally_blocked INTEGER NOT NULL DEFAULT 0
                    CHECK (externally_blocked IN (0, 1)),
                repeat TEXT,
                successor_id TEXT,
                successor_created_updated_at TEXT
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
            ("completed_at", "TEXT"),
            ("due_date", "TEXT"),
            (
                "externally_blocked",
                "INTEGER NOT NULL DEFAULT 0 CHECK (externally_blocked IN (0, 1))",
            ),
            ("repeat", "TEXT"),
            ("successor_id", "TEXT"),
            ("successor_created_updated_at", "TEXT"),
        ):
            if column not in columns:
                self._connection.execute(
                    f"ALTER TABLE tasks ADD COLUMN {column} {sql_type}"
                )
        self._connection.execute(
            """
            CREATE TABLE IF NOT EXISTS task_dependencies (
                task_id TEXT NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
                prerequisite_id TEXT NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
                PRIMARY KEY (task_id, prerequisite_id),
                CHECK (task_id != prerequisite_id)
            )
            """
        )
        self._connection.execute(
            """
            CREATE INDEX IF NOT EXISTS task_dependencies_prerequisite
            ON task_dependencies(prerequisite_id)
            """
        )
        self._connection.commit()

    def save(self, task: Task) -> None:
        """Write the task snapshot and commit it before returning."""
        self.save_many([task])

    def save_many(self, tasks: list[Task]) -> None:
        """Save snapshots atomically, retaining the historical stored status name."""
        if not tasks:
            return
        with self._connection:
            self._connection.executemany(
                """
                INSERT INTO tasks
                    (id, title, status, created_at, updated_at,
                     priority, duration_minutes, project_id, on_deck_since, completed_at,
                     externally_blocked, due_date, repeat, successor_id,
                     successor_created_updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    title = excluded.title,
                    status = excluded.status,
                    created_at = excluded.created_at,
                    updated_at = excluded.updated_at,
                    priority = excluded.priority,
                    duration_minutes = excluded.duration_minutes,
                    project_id = excluded.project_id,
                    on_deck_since = excluded.on_deck_since,
                    completed_at = excluded.completed_at,
                    externally_blocked = excluded.externally_blocked,
                    due_date = excluded.due_date,
                    repeat = excluded.repeat,
                    successor_id = excluded.successor_id,
                    successor_created_updated_at = excluded.successor_created_updated_at
                """,
                [self._task_values(task) for task in tasks],
            )

    def save_and_delete(self, task: Task, task_id: UUID) -> None:
        """Save a restored snapshot and remove its successor atomically."""
        with self._connection:
            if self.get(task.id) is None:
                raise KeyError(task.id)
            if self.get(task_id) is None:
                raise KeyError(task_id)
            cursor = self._connection.execute(
                """UPDATE tasks SET title = ?, status = ?, created_at = ?, updated_at = ?,
                   priority = ?, duration_minutes = ?, project_id = ?, on_deck_since = ?,
                   completed_at = ?, externally_blocked = ?, due_date = ?, repeat = ?,
                   successor_id = ?, successor_created_updated_at = ? WHERE id = ?""",
                self._task_values(task)[1:] + (str(task.id),),
            )
            if cursor.rowcount == 0:
                raise KeyError(task.id)
            cursor = self._connection.execute(
                "DELETE FROM tasks WHERE id = ?", (str(task_id),)
            )
            if cursor.rowcount == 0:
                raise KeyError(task_id)

    def has_dependency_links(self, task_id: UUID) -> bool:
        """Check both sides of dependency links for a task."""
        row = self._connection.execute(
            """SELECT EXISTS (SELECT 1 FROM task_dependencies
               WHERE task_id = ? OR prerequisite_id = ?)""",
            (str(task_id), str(task_id)),
        ).fetchone()
        return bool(row[0])

    @staticmethod
    def _task_values(task: Task) -> tuple[object, ...]:
        """Convert a task snapshot to the values stored by SQLite."""
        return (
            str(task.id),
            task.title,
            "on_deck" if task.status is TaskStatus.ON_HEAP else task.status.value,
            task.created_at.isoformat(),
            task.updated_at.isoformat(),
            task.priority.value if task.priority is not None else None,
            task.duration.minutes,
            str(task.project_id) if task.project_id else None,
            task.on_heap_since.isoformat() if task.on_heap_since else None,
            task.completed_at.isoformat() if task.completed_at else None,
            task.externally_blocked,
            task.due_date.isoformat() if task.due_date else None,
            (
                json.dumps(
                    {
                        "unit": task.repeat.unit.value,
                        "interval": task.repeat.interval_as_decimal(),
                    }
                )
                if task.repeat is not None
                else None
            ),
            str(task.successor_id) if task.successor_id else None,
            (
                task.successor_created_updated_at.isoformat()
                if task.successor_created_updated_at
                else None
            ),
        )

    def delete(self, task_id: UUID) -> None:
        """Remove a task and its dependency links; missing IDs raise KeyError."""
        self.delete_many([task_id])

    def delete_many(self, task_ids: list[UUID]) -> None:
        """Commit all task/link deletions together; roll back if any deletion fails.

        Missing IDs raise KeyError. Empty batches do nothing; repeated IDs count once.
        """
        if not task_ids:
            return
        with self._connection:
            for task_id in dict.fromkeys(task_ids):
                cursor = self._connection.execute(
                    "DELETE FROM tasks WHERE id = ?", (str(task_id),)
                )
                if cursor.rowcount == 0:
                    raise KeyError(task_id)

    def add_dependency(
        self, task_id: UUID, prerequisite_id: UUID, updated_at: datetime
    ) -> None:
        """Commit a new link and its dependent task's timestamp together."""
        with self._connection:
            cursor = self._connection.execute(
                """
                INSERT INTO task_dependencies (task_id, prerequisite_id)
                VALUES (?, ?)
                ON CONFLICT(task_id, prerequisite_id) DO NOTHING
                """,
                (str(task_id), str(prerequisite_id)),
            )
            if cursor.rowcount:
                self._connection.execute(
                    "UPDATE tasks SET updated_at = ? WHERE id = ?",
                    (updated_at.isoformat(), str(task_id)),
                )

    def remove_dependency(
        self, task_id: UUID, prerequisite_id: UUID, updated_at: datetime
    ) -> None:
        """Commit a link removal and its dependent task's timestamp together."""
        with self._connection:
            cursor = self._connection.execute(
                """
                DELETE FROM task_dependencies
                WHERE task_id = ? AND prerequisite_id = ?
                """,
                (str(task_id), str(prerequisite_id)),
            )
            if cursor.rowcount:
                self._connection.execute(
                    "UPDATE tasks SET updated_at = ? WHERE id = ?",
                    (updated_at.isoformat(), str(task_id)),
                )

    def list_dependencies(self, task_id: UUID) -> list[UUID]:
        """Load prerequisite IDs in ascending ID order."""
        rows = self._connection.execute(
            """
            SELECT prerequisite_id FROM task_dependencies
            WHERE task_id = ? ORDER BY prerequisite_id
            """,
            (str(task_id),),
        ).fetchall()
        return [UUID(row[0]) for row in rows]

    def get_dependency_blocking(self, task_ids: list[UUID]) -> dict[UUID, bool]:
        """Check unfinished direct prerequisites in 1 query, omitting missing IDs."""
        if not task_ids:
            return {}
        unique_ids = [str(task_id) for task_id in dict.fromkeys(task_ids)]
        placeholders = ", ".join("?" for _ in unique_ids)
        rows = self._connection.execute(
            f"""
            SELECT task.id, EXISTS (
                SELECT 1 FROM task_dependencies AS dependency
                JOIN tasks AS prerequisite ON prerequisite.id = dependency.prerequisite_id
                WHERE dependency.task_id = task.id AND prerequisite.status != ?
            )
            FROM tasks AS task
            WHERE task.id IN ({placeholders})
            """,
            (TaskStatus.COMPLETED.value, *unique_ids),
        ).fetchall()
        return {UUID(task_id): bool(blocked) for task_id, blocked in rows}

    def get(self, task_id: UUID) -> Task | None:
        """Load an independent task snapshot, or None for an absent ID."""
        row = self._connection.execute(
            """
            SELECT id, title, status, created_at, updated_at,
                   priority, duration_minutes, project_id, on_deck_since, completed_at,
                   externally_blocked, due_date, repeat, successor_id,
                   successor_created_updated_at
            FROM tasks WHERE id = ?
            """,
            (str(task_id),),
        ).fetchone()
        if row is None:
            return None
        return self._task_from_row(row)

    def list_unfinished(self) -> list[Task]:
        """Load unfinished snapshots for explicit Python-side normalization."""
        rows = self._connection.execute(
            """
            SELECT id, title, status, created_at, updated_at,
                   priority, duration_minutes, project_id, on_deck_since, completed_at,
                   externally_blocked, due_date, repeat, successor_id,
                   successor_created_updated_at
            FROM tasks WHERE status != ? ORDER BY id
            """,
            (TaskStatus.COMPLETED.value,),
        ).fetchall()
        return [self._task_from_row(row) for row in rows]

    def list_inbox(self) -> list[Task]:
        """Load unfinished incomplete snapshots ordered by creation time, then ID."""
        rows = self._connection.execute(
            """
            SELECT id, title, status, created_at, updated_at,
                   priority, duration_minutes, project_id, on_deck_since, completed_at,
                   externally_blocked, due_date, repeat, successor_id,
                   successor_created_updated_at
            FROM tasks
            WHERE status != ? AND (priority IS NULL OR duration_minutes IS NULL)
            ORDER BY created_at, id
            """,
            (TaskStatus.COMPLETED.value,),
        ).fetchall()
        return [self._task_from_row(row) for row in rows]

    def list_on_heap(self) -> list[Task]:
        """Load qualifying unfinished snapshots ordered by age, then ID."""
        rows = self._connection.execute(
            """
            SELECT id, title, status, created_at, updated_at,
                   priority, duration_minutes, project_id, on_deck_since, completed_at,
                   externally_blocked, due_date, repeat, successor_id,
                   successor_created_updated_at
            FROM tasks
            WHERE status != ? AND priority IS NOT NULL AND duration_minutes IS NOT NULL
            ORDER BY on_deck_since, id
            """,
            (TaskStatus.COMPLETED.value,),
        ).fetchall()
        return [self._task_from_row(row) for row in rows]

    def list_for_project(self, project_id: UUID) -> list[Task]:
        """Load every task assigned to a project, including completed tasks."""
        rows = self._connection.execute(
            """
            SELECT id, title, status, created_at, updated_at,
                   priority, duration_minutes, project_id, on_deck_since, completed_at,
                   externally_blocked, due_date, repeat, successor_id,
                   successor_created_updated_at
            FROM tasks WHERE project_id = ? ORDER BY created_at, id
            """,
            (str(project_id),),
        ).fetchall()
        return [self._task_from_row(row) for row in rows]

    @staticmethod
    def _task_from_row(
        row: tuple[
            str,
            str,
            str,
            str,
            str,
            int | None,
            int | None,
            str | None,
            str | None,
            str | None,
            int,
            str | None,
            str | None,
            str | None,
            str | None,
        ],
    ) -> Task:
        """Load a snapshot, translating the historical status into heap vocabulary."""
        repeat_data = json.loads(row[12]) if row[12] is not None else None
        return Task(
            id=UUID(row[0]),
            title=row[1],
            status=TaskStatus.ON_HEAP if row[2] == "on_deck" else TaskStatus(row[2]),
            created_at=datetime.fromisoformat(row[3]),
            updated_at=datetime.fromisoformat(row[4]),
            priority=Priority(row[5]) if row[5] is not None else None,
            duration=Duration(row[6]),
            project_id=UUID(row[7]) if row[7] is not None else None,
            on_heap_since=datetime.fromisoformat(row[8]) if row[8] else None,
            completed_at=datetime.fromisoformat(row[9]) if row[9] else None,
            externally_blocked=bool(row[10]),
            due_date=date.fromisoformat(row[11]) if row[11] is not None else None,
            repeat=(
                RepeatRule(
                    unit=repeat_data["unit"],
                    interval=RepeatRule.parse_interval(repeat_data["interval"]),
                )
                if repeat_data is not None
                else None
            ),
            successor_id=UUID(row[13]) if row[13] is not None else None,
            successor_created_updated_at=(
                datetime.fromisoformat(row[14]) if row[14] is not None else None
            ),
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
