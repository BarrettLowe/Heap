from __future__ import annotations

import sqlite3
from datetime import datetime
from pathlib import Path
from types import TracebackType
from uuid import UUID

from heap.logic.project import Project, ProjectStatus
from heap.logic.project_store import ProjectStore


class SQLiteProjectStore(ProjectStore):
    """Save and retrieve projects using a SQLite connection."""

    def __init__(self, database: Path) -> None:
        """Open the database and create project storage if it does not exist."""
        self._connection = sqlite3.connect(database)
        self._connection.execute(
            """
            CREATE TABLE IF NOT EXISTS projects (
                id TEXT PRIMARY KEY NOT NULL,
                name TEXT NOT NULL,
                description TEXT,
                status TEXT NOT NULL,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                completed_at TEXT,
                icon TEXT,
                color TEXT
            )
            """
        )
        self._connection.commit()

    def save(self, project: Project) -> None:
        """Write the project snapshot and commit it before returning."""
        with self._connection:
            self._connection.execute(
                """
                INSERT INTO projects
                    (id, name, description, status, created_at, updated_at, completed_at,
                     icon, color)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    name = excluded.name,
                    description = excluded.description,
                    status = excluded.status,
                    created_at = excluded.created_at,
                    updated_at = excluded.updated_at,
                    completed_at = excluded.completed_at,
                    icon = excluded.icon,
                    color = excluded.color
                """,
                (
                    str(project.id),
                    project.name,
                    project.description,
                    project.status.value,
                    project.created_at.isoformat(),
                    project.updated_at.isoformat(),
                    project.completed_at.isoformat() if project.completed_at else None,
                    project.icon,
                    project.color,
                ),
            )

    def get(self, project_id: UUID) -> Project | None:
        """Load an independent project snapshot, or None for an absent ID."""
        row = self._connection.execute(
            """
            SELECT id, name, description, status, created_at, updated_at, completed_at,
                   icon, color
            FROM projects WHERE id = ?
            """,
            (str(project_id),),
        ).fetchone()
        if row is None:
            return None
        return Project(
            id=UUID(row[0]),
            name=row[1],
            description=row[2],
            status=ProjectStatus(row[3]),
            created_at=datetime.fromisoformat(row[4]),
            updated_at=datetime.fromisoformat(row[5]),
            completed_at=datetime.fromisoformat(row[6]) if row[6] else None,
            icon=row[7],
            color=row[8],
        )

    def list_all(self) -> list[Project]:
        """Load every project ordered by case-insensitive name, then ID."""
        rows = self._connection.execute(
            """
            SELECT id, name, description, status, created_at, updated_at, completed_at,
                   icon, color
            FROM projects ORDER BY name COLLATE NOCASE, name, id
            """
        ).fetchall()
        return [self._project_from_row(row) for row in rows]

    def delete(self, project_id: UUID) -> None:
        """Delete a project, its tasks, and their dependency links atomically."""
        with self._connection:
            cursor = self._connection.execute(
                "DELETE FROM projects WHERE id = ?", (str(project_id),)
            )
            if cursor.rowcount == 0:
                raise KeyError(project_id)
            self._connection.execute(
                """
                DELETE FROM task_dependencies
                WHERE task_id IN (SELECT id FROM tasks WHERE project_id = ?)
                   OR prerequisite_id IN (SELECT id FROM tasks WHERE project_id = ?)
                """,
                (str(project_id), str(project_id)),
            )
            self._connection.execute(
                "DELETE FROM tasks WHERE project_id = ?", (str(project_id),)
            )

    @staticmethod
    def _project_from_row(
        row: tuple[
            str,
            str,
            str | None,
            str,
            str,
            str,
            str | None,
            str | None,
            str | None,
        ],
    ) -> Project:
        """Convert a stored row into an independent project snapshot."""
        return Project(
            id=UUID(row[0]),
            name=row[1],
            description=row[2],
            status=ProjectStatus(row[3]),
            created_at=datetime.fromisoformat(row[4]),
            updated_at=datetime.fromisoformat(row[5]),
            completed_at=datetime.fromisoformat(row[6]) if row[6] else None,
            icon=row[7],
            color=row[8],
        )

    def close(self) -> None:
        """Close the database connection."""
        self._connection.close()

    def __enter__(self) -> SQLiteProjectStore:
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
