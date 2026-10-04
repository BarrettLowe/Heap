from __future__ import annotations

import sqlite3
from dataclasses import replace
from datetime import UTC, datetime
from pathlib import Path
from uuid import UUID, uuid4

import pytest
from pytest import MonkeyPatch

from heap.logic import task_operator
from heap.logic.duration import Duration
from heap.logic.priority import Priority
from heap.logic.task import Task, TaskStatus
from heap.logic.task_operator import TaskOperator
from heap.persistence.sqlite_task_store import SQLiteTaskStore

CREATED = datetime(2026, 1, 2, 12, 0, tzinfo=UTC)
ON_HEAP = datetime(2026, 1, 3, 12, 0, tzinfo=UTC)
EDITED = datetime(2026, 1, 4, 12, 0, tzinfo=UTC)


def organize(tasks: TaskOperator, task: Task, *, waiting: bool = False) -> Task:
    """Save all editable fields with both organization requirements present."""
    return tasks.organize_task(
        task.id,
        title="Organized task",
        priority=Priority.P2,
        duration=Duration.THIRTY_MINUTES,
        externally_blocked=waiting,
        project_id=task.project_id,
    )


def test_atomic_organization_saves_once_reads_time_once_and_preserves_data(
    tmp_path: Path,
    monkeypatch: MonkeyPatch,
) -> None:
    """The complete edit persists together without altering unrelated fields/links."""
    database = tmp_path / "heap.sqlite"
    monkeypatch.setattr(task_operator, "current_time", lambda: CREATED)
    with SQLiteTaskStore(database) as store:
        tasks = TaskOperator(store)
        prerequisite = tasks.capture("Order supplies")
        original = replace(tasks.capture("Repair fence"), project_id=uuid4())
        store.save(original)
        tasks.add_dependency(original.id, prerequisite.id)
        saves = 0
        time_reads = 0
        real_save = store.save

        def read_time() -> datetime:
            """Count time reads and return the entry instant."""
            nonlocal time_reads
            time_reads += 1
            return ON_HEAP

        def count_save(task: Task) -> None:
            """Count snapshots while using real persistence."""
            nonlocal saves
            saves += 1
            real_save(task)

        monkeypatch.setattr(task_operator, "current_time", read_time)
        monkeypatch.setattr(store, "save", count_save)
        saved = organize(tasks, original, waiting=True)
        assert saves == time_reads == 1

    assert saved == replace(
        original,
        title="Organized task",
        priority=Priority.P2,
        duration=Duration.THIRTY_MINUTES,
        externally_blocked=True,
        status=TaskStatus.ON_HEAP,
        on_heap_since=ON_HEAP,
        updated_at=ON_HEAP,
    )
    with SQLiteTaskStore(database) as store:
        assert store.get(original.id) == saved
        assert store.list_dependencies(original.id) == [prerequisite.id]
        assert TaskOperator(store).list_on_heap() == [saved]
        assert TaskOperator(store).list_inbox() == [prerequisite]


@pytest.mark.parametrize("qualified", [False, True])
def test_no_op_does_not_save_or_read_time(
    tmp_path: Path,
    monkeypatch: MonkeyPatch,
    qualified: bool,
) -> None:
    """Unchanged final snapshots do not write or advance timestamps."""
    with SQLiteTaskStore(tmp_path / "heap.sqlite") as store:
        tasks = TaskOperator(store)
        original = tasks.capture("Repair fence")
        if qualified:
            original = organize(tasks, original)

        def unexpected_time() -> datetime:
            """Fail if a no-op reads time."""
            pytest.fail("No-op read time")

        def unexpected_save(task: Task) -> None:
            """Fail if a no-op saves."""
            pytest.fail("No-op saved")

        monkeypatch.setattr(task_operator, "current_time", unexpected_time)
        monkeypatch.setattr(store, "save", unexpected_save)
        assert (
            tasks.organize_task(
                original.id,
                title=original.title,
                priority=original.priority,
                duration=original.duration,
                externally_blocked=original.externally_blocked,
                project_id=original.project_id,
            )
            == original
        )
        if qualified:
            assert tasks.move_to_heap(original.id) == original


@pytest.mark.parametrize(
    ("priority", "duration"),
    [
        (None, Duration.THIRTY_MINUTES),
        (Priority.P2, Duration.UNKNOWN),
        (None, Duration.UNKNOWN),
    ],
)
def test_clear_and_restore_requirements_automatically_change_placement_and_age(
    tmp_path: Path,
    monkeypatch: MonkeyPatch,
    priority: Priority | None,
    duration: Duration,
) -> None:
    """Each/both clears leave the pool; restoring requirements starts a new age."""
    database = tmp_path / "heap.sqlite"
    with SQLiteTaskStore(database) as store:
        tasks = TaskOperator(store)
        original = tasks.capture("Repair fence")
        monkeypatch.setattr(task_operator, "current_time", lambda: ON_HEAP)
        saved = organize(tasks, original, waiting=True)
        monkeypatch.setattr(task_operator, "current_time", lambda: EDITED)
        cleared = tasks.organize_task(
            saved.id,
            title=saved.title,
            priority=priority,
            duration=duration,
            externally_blocked=True,
            project_id=saved.project_id,
        )
        assert cleared.status is TaskStatus.INBOX
        assert cleared.on_heap_since is None
        restored = organize(tasks, cleared, waiting=True)
        assert restored.status is TaskStatus.ON_HEAP
        assert restored.on_heap_since == EDITED
    with SQLiteTaskStore(database) as store:
        assert store.get(saved.id) == restored


@pytest.mark.parametrize("duration_first", [False, True])
def test_both_setter_orders_auto_qualify_and_preserve_age_on_edit(
    tmp_path: Path,
    monkeypatch: MonkeyPatch,
    duration_first: bool,
) -> None:
    """Whichever setter supplies the last requirement starts time on the heap."""
    with SQLiteTaskStore(tmp_path / "heap.sqlite") as store:
        tasks = TaskOperator(store)
        original = tasks.capture("Repair fence")
        monkeypatch.setattr(task_operator, "current_time", lambda: ON_HEAP)
        if duration_first:
            tasks.set_duration(original.id, Duration.THIRTY_MINUTES)
            saved = tasks.set_priority(original.id, Priority.P2)
        else:
            tasks.set_priority(original.id, Priority.P2)
            saved = tasks.set_duration(original.id, Duration.THIRTY_MINUTES)
        assert saved.status is TaskStatus.ON_HEAP
        assert saved.on_heap_since == ON_HEAP
        monkeypatch.setattr(task_operator, "current_time", lambda: EDITED)
        edited = organize(tasks, saved, waiting=True)
        assert edited.on_heap_since == ON_HEAP
        assert edited.updated_at == EDITED
        unblocked = tasks.set_externally_blocked(saved.id, False)
        assert unblocked.on_heap_since == ON_HEAP
        assert unblocked.status is TaskStatus.ON_HEAP


@pytest.mark.parametrize(
    "writer", ["title", "project", "external", "priority", "duration"]
)
def test_snapshot_edit_writers_normalize_legacy_ready_inbox(
    tmp_path: Path,
    monkeypatch: MonkeyPatch,
    writer: str,
) -> None:
    """Even unchanged field edits normalize legacy organization when needed."""
    with SQLiteTaskStore(tmp_path / "heap.sqlite") as store:
        tasks = TaskOperator(store)
        legacy = replace(
            tasks.capture("Legacy"), priority=Priority.P2, duration=Duration.ONE_HOUR
        )
        store.save(legacy)
        reads = 0
        saves = 0
        real_save = store.save

        def read_time() -> datetime:
            """Count the edit's single time read."""
            nonlocal reads
            reads += 1
            return EDITED

        def count_save(task: Task) -> None:
            """Count the edit's single snapshot save."""
            nonlocal saves
            saves += 1
            real_save(task)

        monkeypatch.setattr(task_operator, "current_time", read_time)
        monkeypatch.setattr(store, "save", count_save)
        writers = {
            "title": lambda: tasks.set_title(legacy.id, legacy.title),
            "project": lambda: tasks.set_project(legacy.id, None),
            "external": lambda: tasks.set_externally_blocked(legacy.id, False),
            "priority": lambda: tasks.set_priority(legacy.id, legacy.priority),
            "duration": lambda: tasks.set_duration(legacy.id, legacy.duration),
        }
        saved = writers[writer]()
        assert saved == replace(
            legacy,
            status=TaskStatus.ON_HEAP,
            on_heap_since=EDITED,
            updated_at=EDITED,
        )
        assert reads == saves == 1
        assert writers[writer]() == saved
        assert reads == saves == 1


def test_completed_tasks_are_terminal_and_organization_rejects_before_time(
    tmp_path: Path,
    monkeypatch: MonkeyPatch,
) -> None:
    """Other setters may edit retained data but never resurrect completed tasks."""
    with SQLiteTaskStore(tmp_path / "heap.sqlite") as store:
        tasks = TaskOperator(store)
        completed = tasks.complete(tasks.capture("Finished").id)
        tasks.set_priority(completed.id, Priority.P2)
        updated = tasks.set_duration(completed.id, Duration.ONE_HOUR)
        assert updated.status is TaskStatus.COMPLETED
        assert updated.completed_at == completed.completed_at
        assert updated.on_heap_since is None

        def unexpected_time() -> datetime:
            """Fail if rejected organization reads time."""
            pytest.fail("Rejected edit read time")

        monkeypatch.setattr(task_operator, "current_time", unexpected_time)
        with pytest.raises(ValueError, match="completed"):
            organize(tasks, updated)
        with pytest.raises(KeyError):
            organize(tasks, replace(updated, id=uuid4()))
        assert store.get(completed.id) == updated


def test_failed_snapshot_update_rolls_back_fields_flag_and_links(
    tmp_path: Path,
) -> None:
    """SQLite update failure cannot persist any of the final editable fields."""
    database = tmp_path / "heap.sqlite"
    with SQLiteTaskStore(database) as store:
        tasks = TaskOperator(store)
        original = tasks.capture("Repair fence")
        prerequisite = tasks.capture("Order supplies")
        tasks.add_dependency(original.id, prerequisite.id)
        original = tasks.get(original.id)
    with sqlite3.connect(database) as connection:
        connection.execute("""
            CREATE TRIGGER reject_update BEFORE UPDATE ON tasks
            BEGIN SELECT RAISE(ABORT, 'failed update'); END
        """)
    with (
        SQLiteTaskStore(database) as store,
        pytest.raises(sqlite3.IntegrityError, match="failed update"),
    ):
        organize(TaskOperator(store), original, waiting=True)
    with SQLiteTaskStore(database) as store:
        assert store.get(original.id) == original
        assert store.list_dependencies(original.id) == [prerequisite.id]


def test_lists_query_qualification_include_waiting_and_break_age_ties(
    tmp_path: Path,
) -> None:
    """Lists partition unfinished work by requirements, not independent status."""
    with SQLiteTaskStore(tmp_path / "heap.sqlite") as store:
        tasks = TaskOperator(store)
        original = tasks.capture("Seed")
        store.delete(original.id)
        oldest = replace(
            original,
            id=UUID(int=5),
            priority=Priority.P2,
            duration=Duration.ONE_HOUR,
            on_heap_since=ON_HEAP,
            status=TaskStatus.ON_HEAP,
            externally_blocked=True,
        )
        low = replace(oldest, id=UUID(int=3), on_heap_since=EDITED)
        high = replace(low, id=UUID(int=9), status=TaskStatus.INBOX)
        incomplete = replace(oldest, id=UUID(int=20), priority=None, on_heap_since=None)
        completed = replace(oldest, id=UUID(int=1), status=TaskStatus.COMPLETED)
        store.save_many([high, oldest, incomplete, completed, low])
        store.add_dependency(oldest.id, incomplete.id, EDITED)
        assert tasks.get_dependency_blocking([oldest.id]) == {oldest.id: True}
        listed = tasks.list_on_heap()
        assert [task.id for task in listed] == [oldest.id, low.id, high.id]
        assert tasks.list_inbox() == [incomplete]
        listed[0].title = "Local mutation"
        assert tasks.get(oldest.id).title == oldest.title
        assert tasks.list_on_heap()[0].title == oldest.title
