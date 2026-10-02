from datetime import UTC, datetime
from pathlib import Path
from uuid import uuid4

from pytest import MonkeyPatch

from heap.logic import task_operator
from heap.logic.task import TaskStatus
from heap.logic.task_operator import TaskOperator
from heap.persistence.sqlite_task_store import SQLiteTaskStore


# Cases: title-only capture survives reopening; unknown ID returns None;
# changing a loaded task stays in memory until explicitly saved.


def test_captured_inbox_task_survives_database_reopen(
    tmp_path: Path, monkeypatch: MonkeyPatch
) -> None:
    """Capture saves the title, inbox status, ID, and fixed timestamps."""
    now = datetime(2026, 1, 2, 12, 0, tzinfo=UTC)
    monkeypatch.setattr(task_operator, "current_time", lambda: now)
    database = tmp_path / "tasks.sqlite"

    with SQLiteTaskStore(database) as store:
        task = TaskOperator(store).capture("Repair the fence")

    with SQLiteTaskStore(database) as store:
        saved = store.get(task.id)

    assert saved == task
    assert saved is not task
    assert task.title == "Repair the fence"
    assert task.status is TaskStatus.INBOX
    assert task.created_at == now
    assert task.updated_at == now


def test_unknown_task_id_returns_none(tmp_path: Path) -> None:
    """Retrieving an absent task returns None."""
    with SQLiteTaskStore(tmp_path / "tasks.sqlite") as store:
        assert store.get(uuid4()) is None


def test_task_changes_persist_only_after_explicit_save(tmp_path: Path) -> None:
    """Changing a dataclass does not write to storage by itself."""
    database = tmp_path / "tasks.sqlite"
    with SQLiteTaskStore(database) as store:
        task = TaskOperator(store).capture("Repair the fence")
        task.title = "Repair the north fence"
        saved = store.get(task.id)
        assert saved is not None
        assert saved.title == "Repair the fence"
        store.save(task)

    with SQLiteTaskStore(database) as store:
        assert store.get(task.id) == task
