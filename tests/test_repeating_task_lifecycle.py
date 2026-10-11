import sqlite3
from datetime import UTC, date, datetime
from pathlib import Path
from uuid import UUID

import pytest

from heap.logic import task_operator
from heap.logic.duration import Duration
from heap.logic.priority import Priority
from heap.logic.recurrence import RepeatRule, RepeatUnit
from heap.logic.task import Task, TaskStatus
from heap.logic.task_operator import TaskOperator
from heap.persistence.sqlite_task_store import SQLiteTaskStore


CREATED = datetime(2026, 10, 1, tzinfo=UTC)
COMPLETED = datetime(2026, 10, 2, tzinfo=UTC)


def repeating_heap_task(store: SQLiteTaskStore) -> tuple[TaskOperator, Task]:
    """Create one qualified repeating task with saved Heap age."""
    operator = TaskOperator(store)
    task = operator.capture("Clean tractor filter")
    task = operator.organize_task(
        task.id, title=task.title, priority=Priority.P2,
        duration=Duration.THIRTY_MINUTES, externally_blocked=True,
        due_date=date(2026, 10, 1),
        repeat=RepeatRule(RepeatUnit.MONTHS, 1),
    )
    return operator, task


def test_completion_saves_one_successor_and_reopening_preserves_all_fields(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Persist a single successor with copied settings and reset transient state."""
    database = tmp_path / "heap.sqlite"
    monkeypatch.setattr(task_operator, "current_time", lambda: CREATED)
    with SQLiteTaskStore(database) as store:
        operator, original = repeating_heap_task(store)
        unrelated = operator.capture("Prepare tools")
        operator.add_dependency(unrelated.id, original.id)
        monkeypatch.setattr(task_operator, "current_time", lambda: COMPLETED)
        completed = operator.complete_on_heap(original.id, date(2025, 1, 31))
        successor_id = completed.successor_id
        assert successor_id is not None
        successor = store.get(successor_id)
        assert successor is not None
        assert successor.status is TaskStatus.ON_HEAP
        assert successor.title == original.title
        assert successor.project_id == original.project_id
        assert successor.priority == original.priority
        assert successor.duration == original.duration
        assert successor.repeat == original.repeat
        assert successor.due_date == date(2025, 2, 28)
        assert successor.externally_blocked is False
        assert successor.on_heap_since == COMPLETED
        assert successor.created_at == successor.updated_at == COMPLETED
        assert completed.due_date == original.due_date
        assert store.list_dependencies(unrelated.id) == [original.id]
        assert store.list_dependencies(successor.id) == []
        assert operator.complete_on_heap(original.id) == completed

    with SQLiteTaskStore(database) as store:
        assert store.get(original.id) == completed
        assert store.get(successor_id) == successor
        assert store.list_inbox() == [store.get(unrelated.id)]
        assert store.list_on_heap() == [successor]
        assert store.list_for_project(UUID(int=99)) == []


def test_undo_deletes_unchanged_successor_and_recompletion_makes_new_one(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Remove only the untouched successor and allow a later new completion."""
    monkeypatch.setattr(task_operator, "current_time", lambda: CREATED)
    with SQLiteTaskStore(tmp_path / "heap.sqlite") as store:
        operator, original = repeating_heap_task(store)
        monkeypatch.setattr(task_operator, "current_time", lambda: COMPLETED)
        completed = operator.complete_on_heap(original.id, date(2026, 10, 5))
        first_successor = completed.successor_id
        restored = operator.undo_completion(original.id)
        assert restored.status is TaskStatus.ON_HEAP
        assert restored.on_heap_since == original.on_heap_since
        assert restored.repeat == original.repeat
        assert restored.successor_id is None
        assert first_successor is not None and store.get(first_successor) is None
        recompleted = operator.complete_on_heap(original.id, date(2026, 10, 6))
        assert recompleted.successor_id is not None
        assert recompleted.successor_id != first_successor
        assert len(store.list_on_heap()) == 1


def test_changed_then_reverted_successor_and_any_link_forbid_undo(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Reject Undo after edits or links, but allow it after link removal."""
    monkeypatch.setattr(task_operator, "current_time", lambda: CREATED)
    with SQLiteTaskStore(tmp_path / "heap.sqlite") as store:
        operator, original = repeating_heap_task(store)
        monkeypatch.setattr(task_operator, "current_time", lambda: COMPLETED)
        completed = operator.complete_on_heap(original.id, date(2026, 10, 5))
        successor_id = completed.successor_id
        assert successor_id is not None
        successor = store.get(successor_id)
        assert successor is not None
        monkeypatch.setattr(task_operator, "current_time", lambda: successor.updated_at)
        operator.set_title(successor_id, successor.title + " changed")
        operator.set_title(successor_id, successor.title)
        with pytest.raises(ValueError, match="successor changed"):
            operator.undo_completion(original.id)
        assert store.get(successor_id) is not None

    with SQLiteTaskStore(tmp_path / "linked.sqlite") as store:
        operator, original = repeating_heap_task(store)
        monkeypatch.setattr(task_operator, "current_time", lambda: COMPLETED)
        completed = operator.complete_on_heap(original.id, date(2026, 10, 5))
        successor_id = completed.successor_id
        assert successor_id is not None
        other = operator.capture("Another task")
        operator.add_dependency(other.id, successor_id)
        with pytest.raises(ValueError, match="successor changed"):
            operator.undo_completion(original.id)
        operator.remove_dependency(other.id, successor_id)
        assert operator.undo_completion(original.id).status is TaskStatus.ON_HEAP

    with SQLiteTaskStore(tmp_path / "outgoing-reverted.sqlite") as store:
        operator, original = repeating_heap_task(store)
        monkeypatch.setattr(task_operator, "current_time", lambda: COMPLETED)
        completed = operator.complete_on_heap(original.id, date(2026, 10, 5))
        successor_id = completed.successor_id
        assert successor_id is not None
        other = operator.capture("Prerequisite")
        operator.add_dependency(successor_id, other.id)
        operator.remove_dependency(successor_id, other.id)
        with pytest.raises(ValueError, match="successor changed"):
            operator.undo_completion(original.id)


@pytest.mark.parametrize("successor_change",  ["deleted", "completed", "outgoing_link"])
def test_missing_completed_or_outgoing_link_successor_forbids_undo(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    successor_change: str,
) -> None:
    """Refuse Undo when the saved successor is missing, completed, or linked."""
    monkeypatch.setattr(task_operator, "current_time", lambda: CREATED)
    database = tmp_path / f"{successor_change}.sqlite"
    with SQLiteTaskStore(database) as store:
        operator, original = repeating_heap_task(store)
        monkeypatch.setattr(task_operator, "current_time", lambda: COMPLETED)
        completed = operator.complete_on_heap(original.id, date(2026, 10, 5))
        assert completed.successor_id is not None
        if successor_change == "deleted":
            operator.delete(completed.successor_id)
        elif successor_change == "completed":
            operator.complete(completed.successor_id, date(2026, 10, 5))
        else:
            prerequisite = operator.capture("Prerequisite")
            operator.add_dependency(completed.successor_id, prerequisite.id)
        with pytest.raises(ValueError, match="successor changed"):
            operator.undo_completion(original.id)


def test_deleting_completed_history_keeps_independent_successor(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Deleting one completed occurrence does not remove its successor."""
    monkeypatch.setattr(task_operator, "current_time", lambda: CREATED)
    with SQLiteTaskStore(tmp_path / "heap.sqlite") as store:
        operator, original = repeating_heap_task(store)
        monkeypatch.setattr(task_operator, "current_time", lambda: COMPLETED)
        completed = operator.complete_on_heap(original.id, date(2026, 10, 5))
        assert completed.successor_id is not None
        operator.delete(original.id)
        assert store.get(original.id) is None
        assert store.get(completed.successor_id) is not None


def test_repeat_edits_advance_tokens_and_turning_repeat_off_stops_successors(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Preserve the first due date while edited rules and repeat-off changes save."""
    monkeypatch.setattr(task_operator, "current_time", lambda: CREATED)
    with SQLiteTaskStore(tmp_path / "heap.sqlite") as store:
        operator, original = repeating_heap_task(store)
        edited = operator.organize_task(
            original.id, title=original.title, priority=original.priority,
            duration=original.duration, externally_blocked=original.externally_blocked,
            project_id=original.project_id, due_date=original.due_date,
            repeat=RepeatRule(RepeatUnit.DAYS, 7),
        )
        assert edited.due_date == original.due_date
        assert edited.updated_at > original.updated_at
        reverted = operator.organize_task(
            edited.id, title=edited.title, priority=edited.priority,
            duration=edited.duration, externally_blocked=edited.externally_blocked,
            project_id=edited.project_id, due_date=edited.due_date,
            repeat=original.repeat,
        )
        assert reverted.updated_at > edited.updated_at
        disabled = operator.organize_task(
            reverted.id, title=reverted.title, priority=reverted.priority,
            duration=reverted.duration, externally_blocked=reverted.externally_blocked,
            project_id=reverted.project_id, due_date=reverted.due_date, repeat=None,
        )
        assert disabled.repeat is None
        assert disabled.due_date == original.due_date
        monkeypatch.setattr(task_operator, "current_time", lambda: COMPLETED)
        completed = operator.complete_on_heap(disabled.id)
        assert completed.successor_id is None
        assert store.list_on_heap() == []


def test_completion_and_undo_storage_failures_roll_back_both_tasks(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Roll back original updates when creating or deleting a successor fails."""
    database = tmp_path / "heap.sqlite"
    monkeypatch.setattr(task_operator, "current_time", lambda: CREATED)
    with SQLiteTaskStore(database) as store:
        operator, original = repeating_heap_task(store)
        monkeypatch.setattr(task_operator, "current_time", lambda: COMPLETED)
        store._connection.execute(
            f"""CREATE TRIGGER reject_successor BEFORE INSERT ON tasks
                WHEN NEW.id != '{original.id}'
                BEGIN SELECT RAISE(ABORT, 'injected successor failure'); END"""
        )
        with pytest.raises(sqlite3.IntegrityError, match="injected successor"):
            operator.complete_on_heap(original.id, date(2026, 10, 5))
        assert store.get(original.id) == original
        store._connection.execute("DROP TRIGGER reject_successor")
        completed = operator.complete_on_heap(original.id, date(2026, 10, 5))
        successor_id = completed.successor_id
        assert successor_id is not None
        successor = store.get(successor_id)
        assert successor is not None
        store._connection.execute(
            f"""CREATE TRIGGER reject_successor_delete BEFORE DELETE ON tasks
                WHEN OLD.id = '{successor_id}'
                BEGIN SELECT RAISE(ABORT, 'injected successor deletion failure'); END"""
        )
        with pytest.raises(sqlite3.IntegrityError, match="injected successor deletion"):
            operator.undo_completion(original.id)
        assert store.get(original.id) == completed
        assert store.get(successor_id) == successor
        store._connection.execute("DROP TRIGGER reject_successor_delete")
        assert operator.undo_completion(original.id).status is TaskStatus.ON_HEAP
