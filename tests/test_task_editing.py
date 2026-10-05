from datetime import date, UTC, datetime
from pathlib import Path
from uuid import uuid4

import pytest
from pytest import MonkeyPatch

from heap.logic import task_operator
from heap.logic.duration import Duration
from heap.logic.priority import Priority
from heap.logic.project_operator import ProjectOperator
from heap.logic.task import Task, TaskStatus
from heap.logic.task_operator import TaskOperator
from heap.persistence.sqlite_project_store import SQLiteProjectStore
from heap.persistence.sqlite_task_store import SQLiteTaskStore


# Cases: set/change/clear each field; persist across reopening; leave other
# fields and status alone; unchanged values do not save; missing IDs fail.

CREATED: datetime = datetime(2026, 1, 2, 12, 0, tzinfo=UTC)
EDITED: datetime = datetime(2026, 1, 3, 12, 0, tzinfo=UTC)


@pytest.fixture
def captured_task(tmp_path: Path, monkeypatch: MonkeyPatch) -> Task:
    """Save an inbox task with fixed creation time for editing tests."""
    monkeypatch.setattr(task_operator, "current_time", lambda: CREATED)
    with SQLiteTaskStore(tmp_path / "heap.sqlite") as store:
        return TaskOperator(store).capture("Repair the fence")


@pytest.mark.parametrize("priority", [Priority.P1, Priority.P5])
def test_setting_and_changing_priority_persist_without_activating(
    tmp_path: Path, monkeypatch: MonkeyPatch, captured_task: Task, priority: Priority
) -> None:
    """Priority edits save their timestamp without changing unrelated fields."""
    with SQLiteTaskStore(tmp_path / "heap.sqlite") as store:
        tasks = TaskOperator(store)
        tasks.set_priority(captured_task.id, Priority.P3)
        monkeypatch.setattr(task_operator, "current_time", lambda: EDITED)
        edited = tasks.set_priority(captured_task.id, priority)

    with SQLiteTaskStore(tmp_path / "heap.sqlite") as store:
        assert store.get(captured_task.id) == edited
    assert edited.priority is priority
    assert edited.updated_at == EDITED
    assert edited.created_at == CREATED
    assert edited.status is TaskStatus.INBOX
    assert edited.title == captured_task.title
    assert edited.duration is Duration.UNKNOWN


def test_clearing_priority_persists(
    tmp_path: Path, monkeypatch: MonkeyPatch, captured_task: Task
) -> None:
    """An assigned priority can be explicitly cleared to None."""
    with SQLiteTaskStore(tmp_path / "heap.sqlite") as store:
        tasks = TaskOperator(store)
        tasks.set_priority(captured_task.id, Priority.P2)
        monkeypatch.setattr(task_operator, "current_time", lambda: EDITED)
        edited = tasks.set_priority(captured_task.id, None)

    with SQLiteTaskStore(tmp_path / "heap.sqlite") as store:
        assert store.get(captured_task.id) == edited
    assert edited.priority is None
    assert edited.updated_at == EDITED


@pytest.mark.parametrize("duration", [Duration.FIVE_MINUTES, Duration.FOUR_HOURS])
def test_setting_and_changing_duration_persist_and_preserve_qualified_age(
    tmp_path: Path, monkeypatch: MonkeyPatch, captured_task: Task, duration: Duration
) -> None:
    """Duration edits save their timestamp without changing unrelated fields."""
    with SQLiteTaskStore(tmp_path / "heap.sqlite") as store:
        tasks = TaskOperator(store)
        tasks.set_duration(captured_task.id, Duration.THIRTY_MINUTES)
        tasks.set_priority(captured_task.id, Priority.P2)
        monkeypatch.setattr(task_operator, "current_time", lambda: EDITED)
        edited = tasks.set_duration(captured_task.id, duration)

    with SQLiteTaskStore(tmp_path / "heap.sqlite") as store:
        assert store.get(captured_task.id) == edited
    assert edited.duration is duration
    assert edited.updated_at == EDITED
    assert edited.created_at == CREATED
    assert edited.status is TaskStatus.ON_HEAP
    assert edited.on_heap_since == CREATED
    assert edited.title == captured_task.title
    assert edited.priority is Priority.P2


def test_clearing_duration_persists(
    tmp_path: Path, monkeypatch: MonkeyPatch, captured_task: Task
) -> None:
    """An assigned estimate can be reset to unknown."""
    with SQLiteTaskStore(tmp_path / "heap.sqlite") as store:
        tasks = TaskOperator(store)
        tasks.set_duration(captured_task.id, Duration.THIRTY_MINUTES)
        monkeypatch.setattr(task_operator, "current_time", lambda: EDITED)
        edited = tasks.set_duration(captured_task.id, Duration.UNKNOWN)

    with SQLiteTaskStore(tmp_path / "heap.sqlite") as store:
        assert store.get(captured_task.id) == edited
    assert edited.duration is Duration.UNKNOWN
    assert edited.updated_at == EDITED


def test_unchanged_values_do_not_save_or_change_timestamp(
    tmp_path: Path, monkeypatch: MonkeyPatch, captured_task: Task
) -> None:
    """Assigning existing values is not a meaningful task change."""
    def unexpected_save(task: Task) -> None:
        """Fail if a no-op edit tries to write to storage."""
        pytest.fail("An unchanged task should not be saved")

    monkeypatch.setattr(task_operator, "current_time", lambda: EDITED)
    with SQLiteTaskStore(tmp_path / "heap.sqlite") as store:
        monkeypatch.setattr(store, "save", unexpected_save)
        tasks = TaskOperator(store)
        assert tasks.set_priority(captured_task.id, None) == captured_task
        assert tasks.set_duration(captured_task.id, Duration.UNKNOWN) == captured_task
        assert tasks.set_title(captured_task.id, captured_task.title) == captured_task
        assert tasks.set_project(captured_task.id, None) == captured_task


def test_editing_missing_task_raises_key_error(tmp_path: Path) -> None:
    """Editing does not silently create a task for an unknown ID."""
    with SQLiteTaskStore(tmp_path / "heap.sqlite") as store:
        tasks = TaskOperator(store)
        missing_id = uuid4()
        with pytest.raises(KeyError):
            tasks.set_priority(missing_id, Priority.P2)
        with pytest.raises(KeyError):
            tasks.set_duration(missing_id, Duration.THIRTY_MINUTES)
        with pytest.raises(KeyError):
            tasks.set_title(missing_id, "New title")
        with pytest.raises(KeyError):
            tasks.set_project(missing_id, None)
        assert tasks.list_inbox() == []


def test_title_edit_persists_and_preserves_other_fields(
    tmp_path: Path, monkeypatch: MonkeyPatch, captured_task: Task
) -> None:
    """Title editing saves without changing task status, priority, or duration."""
    with SQLiteTaskStore(tmp_path / "heap.sqlite") as store:
        tasks = TaskOperator(store)
        tasks.set_priority(captured_task.id, Priority.P2)
        tasks.set_duration(captured_task.id, Duration.THIRTY_MINUTES)
        monkeypatch.setattr(task_operator, "current_time", lambda: EDITED)
        edited = tasks.set_title(captured_task.id, "Replace the north fence boards")

    with SQLiteTaskStore(tmp_path / "heap.sqlite") as store:
        assert store.get(captured_task.id) == edited
    assert edited.title == "Replace the north fence boards"
    assert edited.updated_at == EDITED
    assert edited.created_at == CREATED
    assert edited.priority is Priority.P2
    assert edited.duration is Duration.THIRTY_MINUTES
    assert edited.status is TaskStatus.ON_HEAP
    assert edited.on_heap_since == CREATED
    assert edited.project_id is None


def test_project_assignment_reassignment_and_removal_persist(
    tmp_path: Path, monkeypatch: MonkeyPatch, captured_task: Task
) -> None:
    """A task can move between existing projects or become project-less again."""
    database = tmp_path / "heap.sqlite"
    with SQLiteProjectStore(database) as project_store:
        projects = ProjectOperator(project_store)
        first = projects.create("Fence repair")
        second = projects.create("Garden maintenance")
        with SQLiteTaskStore(database) as store:
            tasks = TaskOperator(store, project_store)
            tasks.set_priority(captured_task.id, Priority.P2)
            tasks.set_duration(captured_task.id, Duration.THIRTY_MINUTES)
            monkeypatch.setattr(task_operator, "current_time", lambda: EDITED)
            assigned = tasks.set_project(captured_task.id, first.id)
            assert assigned.project_id == first.id
            assert assigned.updated_at == EDITED
            assert assigned.created_at == CREATED
            assert assigned.title == captured_task.title
            assert assigned.priority is Priority.P2
            assert assigned.duration is Duration.THIRTY_MINUTES
            assert assigned.status is TaskStatus.ON_HEAP
            assert assigned.on_heap_since == CREATED

    with SQLiteProjectStore(database) as project_store:
        with SQLiteTaskStore(database) as store:
            tasks = TaskOperator(store, project_store)
            assert store.get(captured_task.id) == assigned
            assert tasks.list_inbox() == []
            assert tasks.list_on_heap(today=date(2026, 10, 5)) == [assigned]
            reassigned_at = datetime(2026, 1, 4, 12, 0, tzinfo=UTC)
            monkeypatch.setattr(task_operator, "current_time", lambda: reassigned_at)
            moved = tasks.set_project(captured_task.id, second.id)
            assert moved.project_id == second.id
            assert moved.updated_at == reassigned_at

    with SQLiteTaskStore(database) as store:
        assert store.get(captured_task.id) == moved
        removed_at = datetime(2026, 1, 5, 12, 0, tzinfo=UTC)
        monkeypatch.setattr(task_operator, "current_time", lambda: removed_at)
        removed = TaskOperator(store).set_project(captured_task.id, None)
        assert removed.project_id is None
        assert removed.updated_at == removed_at

    with SQLiteTaskStore(database) as store:
        assert store.get(captured_task.id) == removed


def test_missing_project_rejected_without_changing_saved_task(
    tmp_path: Path, captured_task: Task
) -> None:
    """Assigning an unknown project raises KeyError and leaves the task unchanged."""
    database = tmp_path / "heap.sqlite"
    with SQLiteProjectStore(database) as project_store:
        with SQLiteTaskStore(database) as store:
            with pytest.raises(KeyError):
                TaskOperator(store, project_store).set_project(captured_task.id, uuid4())
            assert store.get(captured_task.id) == captured_task


def test_project_assignment_requires_a_project_store(
    tmp_path: Path, captured_task: Task
) -> None:
    """Assignment cannot skip project existence checks when no store is supplied."""
    with SQLiteTaskStore(tmp_path / "heap.sqlite") as store:
        with pytest.raises(ValueError, match="project store"):
            TaskOperator(store).set_project(captured_task.id, uuid4())
        assert store.get(captured_task.id) == captured_task


def test_reassigning_same_project_does_not_save_or_change_timestamp(
    tmp_path: Path, monkeypatch: MonkeyPatch, captured_task: Task
) -> None:
    """Assigning the current project is not a meaningful change."""
    def unexpected_save(task: Task) -> None:
        """Fail if an unchanged project assignment tries to save."""
        pytest.fail("An unchanged task should not be saved")

    database = tmp_path / "heap.sqlite"
    with SQLiteProjectStore(database) as project_store:
        project = ProjectOperator(project_store).create("Fence repair")
        with SQLiteTaskStore(database) as store:
            tasks = TaskOperator(store, project_store)
            assigned = tasks.set_project(captured_task.id, project.id)
            monkeypatch.setattr(task_operator, "current_time", lambda: EDITED)
            monkeypatch.setattr(store, "save", unexpected_save)
            assert tasks.set_project(captured_task.id, project.id) == assigned
