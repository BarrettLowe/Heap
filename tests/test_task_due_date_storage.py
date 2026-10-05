from dataclasses import replace
from datetime import UTC, date, datetime
from pathlib import Path
import sqlite3
from uuid import UUID, uuid4

import pytest

from heap.logic.task import Task, TaskStatus
from heap.persistence.sqlite_task_store import SQLiteTaskStore


def make_task(project_id: UUID | None = None, due_date: date | None = None) -> Task:
    """Build a stable task snapshot for storage tests."""
    now = datetime(2026, 1, 2, tzinfo=UTC)
    return Task(
        uuid4(),
        "Keep snapshot",
        TaskStatus.INBOX,
        now,
        now,
        project_id=project_id,
        due_date=due_date,
    )


@pytest.mark.parametrize(
    "due_date", [None, date(2024, 2, 29), date(2020, 1, 1), date(2030, 12, 31)]
)
def test_date_round_trips_through_every_read_path_and_reopen(
    tmp_path: Path, due_date: date | None
) -> None:
    """All task lookup paths preserve nullable calendar dates across reopen."""
    database = tmp_path / "tasks.sqlite"
    project_id = uuid4()
    task = make_task(project_id, due_date)
    with SQLiteTaskStore(database) as store:
        store.save(task)
    with SQLiteTaskStore(database) as store:
        assert store.get(task.id) == task
        assert store.list_unfinished() == [task]
        assert store.list_inbox() == [task]
        assert store.list_for_project(project_id) == [task]


def test_bulk_upsert_preserves_dates_and_rolls_back_batch(tmp_path: Path) -> None:
    """An SQLite failure during a batch restores every task to its prior snapshot."""
    database = tmp_path / "tasks.sqlite"
    original = make_task(due_date=date(2028, 2, 29))
    second = make_task(due_date=date(2027, 5, 4))
    changed_original = replace(original, due_date=None, title="Changed")
    changed_second = replace(second, due_date=None, title="Also changed")
    with SQLiteTaskStore(database) as store:
        store.save_many([original, second])
        store._connection.execute(
            f"""
            CREATE TRIGGER reject_second_update
            BEFORE UPDATE ON tasks WHEN OLD.id = '{second.id}'
            BEGIN SELECT RAISE(ABORT, 'forced batch failure'); END
            """
        )
        with pytest.raises(sqlite3.IntegrityError, match="forced batch failure"):
            store.save_many([changed_original, changed_second])
        assert store.get(original.id) == original
        assert store.get(second.id) == second

    with SQLiteTaskStore(database) as store:
        assert store.get(original.id) == original
        assert store.get(second.id) == second


def test_existing_database_rows_default_due_date_to_null(tmp_path: Path) -> None:
    """Adding the nullable date column leaves existing rows undated."""
    database = tmp_path / "legacy.sqlite"
    now = datetime(2026, 1, 2, tzinfo=UTC).isoformat()
    task_id = str(uuid4())
    connection = sqlite3.connect(database)
    connection.execute(
        "CREATE TABLE tasks (id TEXT PRIMARY KEY, title TEXT NOT NULL, status TEXT NOT NULL, created_at TEXT NOT NULL, updated_at TEXT NOT NULL)"
    )
    connection.execute(
        "INSERT INTO tasks VALUES (?, ?, ?, ?, ?)", (task_id, "Old", "inbox", now, now)
    )
    connection.commit()
    connection.close()
    with SQLiteTaskStore(database) as store:
        assert store.get(UUID(task_id)).due_date is None
