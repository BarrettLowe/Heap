from dataclasses import replace
from datetime import UTC, date, datetime, timedelta
from pathlib import Path
import sqlite3

import pytest

from heap.logic import task_operator
from heap.logic.duration import Duration
from heap.logic.priority import Priority
from heap.logic.task import TaskStatus
from heap.logic.task_operator import TaskOperator
from heap.persistence.sqlite_task_store import SQLiteTaskStore

NOW = datetime(2026, 2, 3, 12, tzinfo=UTC)
DUE = date(2026, 2, 10)


def test_due_date_edit_preserves_heap_placement_and_advances_token(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """A due-date-only edit retains placement while monotonically advancing updated_at."""
    with SQLiteTaskStore(tmp_path / "heap.sqlite") as store:
        operator = TaskOperator(store)
        task = operator.capture("task")
        monkeypatch.setattr(task_operator, "current_time", lambda: NOW)
        task = operator.organize_task(
            task.id,
            title=task.title,
            priority=Priority.P2,
            duration=Duration.ONE_HOUR,
            externally_blocked=True,
            project_id=None,
            due_date=None,
        )
        previous = task.updated_at
        saved = operator.organize_task(
            task.id,
            title=task.title,
            priority=task.priority,
            duration=task.duration,
            externally_blocked=True,
            project_id=None,
            due_date=DUE,
        )
        assert saved.due_date == DUE
        assert saved.status is TaskStatus.ON_HEAP
        assert saved.on_heap_since == NOW
        assert saved.externally_blocked is True
        assert saved.updated_at == previous + timedelta(microseconds=1)
        assert store.get(task.id) == saved


def test_identical_due_date_is_noop_and_null_clears(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Repeating a date does not read time or save, and null clears it."""
    with SQLiteTaskStore(tmp_path / "heap.sqlite") as store:
        operator = TaskOperator(store)
        task = replace(operator.capture("task"), due_date=DUE)
        store.save(task)
        monkeypatch.setattr(
            task_operator, "current_time", lambda: pytest.fail("no-op read time")
        )
        assert (
            operator.organize_task(
                task.id,
                title=task.title,
                priority=None,
                duration=Duration.UNKNOWN,
                externally_blocked=False,
                project_id=None,
                due_date=DUE,
            )
            == task
        )
        monkeypatch.setattr(task_operator, "current_time", lambda: NOW)
        cleared = operator.organize_task(
            task.id,
            title=task.title,
            priority=None,
            duration=Duration.UNKNOWN,
            externally_blocked=False,
            project_id=None,
            due_date=None,
        )
        assert cleared.due_date is None


def test_due_date_survives_completion_undo_and_normalization(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Lifecycle snapshots retain due date through completion, undo, and normalization."""
    with SQLiteTaskStore(tmp_path / "heap.sqlite") as store:
        operator = TaskOperator(store)
        task = replace(
            operator.capture("task"),
            due_date=DUE,
            priority=Priority.P2,
            duration=Duration.ONE_HOUR,
        )
        store.save(task)
        monkeypatch.setattr(task_operator, "current_time", lambda: NOW)
        operator.normalize_organization()
        completed = operator.complete_on_heap(task.id)
        assert completed.due_date == DUE
        undone = operator.undo_completion(task.id)
        assert undone.due_date == DUE
        assert undone.on_heap_since == NOW


def test_completed_organization_is_rejected(tmp_path: Path) -> None:
    """Completed tasks reject organization without changing their saved snapshot."""
    with SQLiteTaskStore(tmp_path / "heap.sqlite") as store:
        operator = TaskOperator(store)
        task = replace(operator.capture("task"), due_date=DUE)
        store.save(task)
        completed = operator.complete(task.id)
        with pytest.raises(ValueError, match="completed"):
            operator.organize_task(
                task.id,
                title=task.title,
                priority=None,
                duration=Duration.UNKNOWN,
                externally_blocked=False,
                project_id=None,
                due_date=None,
            )
        assert store.get(task.id) == completed


def test_failed_date_edit_save_preserves_persisted_snapshot(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """A database write failure leaves the previously saved due date unchanged."""
    with SQLiteTaskStore(tmp_path / "heap.sqlite") as store:
        operator = TaskOperator(store)
        original = replace(operator.capture("task"), due_date=DUE)
        store.save(original)

        def fail_save(task: object) -> None:
            """Simulate an SQLite write failure during date-only organization."""
            raise sqlite3.IntegrityError("forced save failure")

        monkeypatch.setattr(store, "save", fail_save)
        with pytest.raises(sqlite3.IntegrityError, match="forced save failure"):
            operator.organize_task(
                original.id,
                title=original.title,
                priority=original.priority,
                duration=original.duration,
                externally_blocked=original.externally_blocked,
                project_id=original.project_id,
                due_date=None,
            )

        assert store.get(original.id) == original
