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
                completed_at TEXT
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
                    (id, name, description, status, created_at, updated_at, completed_at)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    name = excluded.name,
                    description = excluded.description,
                    status = excluded.status,
                    created_at = excluded.created_at,
                    updated_at = excluded.updated_at,
                    completed_at = excluded.completed_at
                """,
                (
                    str(project.id),
                    project.name,
                    project.description,
                    project.status.value,
                    project.created_at.isoformat(),
                    project.updated_at.isoformat(),
                    project.completed_at.isoformat() if project.completed_at else None,
                ),
            )

    def get(self, project_id: UUID) -> Project | None:
        """Load an independent project snapshot, or None for an absent ID."""
        row = self._connection.execute(
            """
            SELECT id, name, description, status, created_at, updated_at, completed_at
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
