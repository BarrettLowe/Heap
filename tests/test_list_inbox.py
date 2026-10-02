import sqlite3
from contextlib import closing
from datetime import UTC, datetime
from pathlib import Path
from uuid import UUID

from pytest import MonkeyPatch

from heap.logic import task_operator
from heap.logic.task_operator import TaskOperator
from heap.persistence.sqlite_task_store import SQLiteTaskStore


# Cases: empty inbox; multiple tasks after reopening; equal-time ordering;
# editing a listed snapshot does not persist; non-inbox rows are excluded.


def test_empty_inbox_returns_empty_list(tmp_path: Path) -> None:
    """Listing an empty inbox returns an empty list."""
    with SQLiteTaskStore(tmp_path / "tasks.sqlite") as store:
        assert TaskOperator(store).list_inbox() == []


def test_inbox_survives_reopening_and_lists_oldest_first(
    tmp_path: Path, monkeypatch: MonkeyPatch
) -> None:
    """Inbox order follows creation time rather than insertion order."""
    database = tmp_path / "tasks.sqlite"
    with SQLiteTaskStore(database) as store:
        tasks = TaskOperator(store)
        monkeypatch.setattr(
            task_operator, "current_time", lambda: datetime(2026, 1, 3, tzinfo=UTC)
        )
        newer = tasks.capture("Repair the fence")
        monkeypatch.setattr(
            task_operator, "current_time", lambda: datetime(2026, 1, 2, tzinfo=UTC)
        )
        older = tasks.capture("Buy fence posts")

    with SQLiteTaskStore(database) as store:
        assert TaskOperator(store).list_inbox() == [older, newer]


def test_inbox_breaks_creation_time_ties_by_id(
    tmp_path: Path, monkeypatch: MonkeyPatch
) -> None:
    """Tasks with equal timestamps have a stable ID-based order."""
    now = datetime(2026, 1, 2, tzinfo=UTC)
    monkeypatch.setattr(task_operator, "current_time", lambda: now)
    with SQLiteTaskStore(tmp_path / "tasks.sqlite") as store:
        tasks = TaskOperator(store)
        monkeypatch.setattr(task_operator, "uuid4", lambda: UUID(int=2))
        second = tasks.capture("Repair the fence")
        monkeypatch.setattr(task_operator, "uuid4", lambda: UUID(int=1))
        first = tasks.capture("Buy fence posts")
        assert tasks.list_inbox() == [first, second]
        assert tasks.list_inbox() == [first, second]


def test_editing_listed_task_does_not_change_saved_inbox(tmp_path: Path) -> None:
    """Listing returns snapshots, not automatically persisted objects."""
    with SQLiteTaskStore(tmp_path / "tasks.sqlite") as store:
        tasks = TaskOperator(store)
        captured = tasks.capture("Repair the fence")
        listed = tasks.list_inbox()
        assert listed[0] is not captured
        listed[0].title = "Repair the north fence"
        assert tasks.list_inbox() == [captured]


def test_inbox_excludes_rows_with_other_statuses(tmp_path: Path) -> None:
    """The inbox query does not load tasks stored in another lifecycle state."""
    database = tmp_path / "tasks.sqlite"
    with SQLiteTaskStore(database) as store:
        tasks = TaskOperator(store)
        inbox = tasks.capture("Buy fence posts")
        completed = tasks.capture("Repair the fence")

    with closing(sqlite3.connect(database)) as connection:
        connection.execute(
            "UPDATE tasks SET status = ? WHERE id = ?",
            ("completed", str(completed.id)),
        )
        connection.commit()

    with SQLiteTaskStore(database) as store:
        assert TaskOperator(store).list_inbox() == [inbox]
