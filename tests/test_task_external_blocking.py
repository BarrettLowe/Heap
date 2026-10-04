import sqlite3
from contextlib import closing
from dataclasses import replace
from datetime import UTC, datetime
from pathlib import Path
from uuid import UUID, uuid4

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


CREATED: datetime = datetime(2026, 1, 2, 12, 0, tzinfo=UTC)
EDITED: datetime = datetime(2026, 1, 3, 12, 0, tzinfo=UTC)


def test_captured_task_defaults_to_not_externally_blocked(tmp_path: Path) -> None:
    """New tasks start with a false manual flag that survives reopening."""
    database = tmp_path / "heap.sqlite"
    with SQLiteTaskStore(database) as store:
        captured = TaskOperator(store).capture("Repair the fence")
        assert captured.externally_blocked is False

    with SQLiteTaskStore(database) as store:
        saved = store.get(captured.id)
        assert saved is not None
        assert saved.externally_blocked is False
        assert TaskOperator(store).list_inbox() == [captured]


@pytest.mark.parametrize(
    "status", [TaskStatus.INBOX, TaskStatus.ON_HEAP, TaskStatus.COMPLETED]
)
@pytest.mark.parametrize("externally_blocked", [False, True])
def test_external_flag_edits_persist_and_preserve_other_fields(
    tmp_path: Path, monkeypatch: MonkeyPatch,
    status: TaskStatus, externally_blocked: bool,
) -> None:
    """Setting or clearing the manual flag changes only it and updated_at."""
    database = tmp_path / "heap.sqlite"
    monkeypatch.setattr(task_operator, "current_time", lambda: CREATED)
    with SQLiteProjectStore(database) as project_store:
        project = ProjectOperator(project_store).create("Fence repair")
        with SQLiteTaskStore(database) as store:
            tasks = TaskOperator(store, project_store)
            captured = tasks.capture("Repair the fence")
            tasks.set_project(captured.id, project.id)
            tasks.set_priority(captured.id, Priority.P2)
            if status is not TaskStatus.INBOX:
                tasks.set_duration(captured.id, Duration.THIRTY_MINUTES)
                tasks.move_to_heap(captured.id)
            if status is TaskStatus.COMPLETED:
                tasks.complete(captured.id)
            before = tasks.set_externally_blocked(captured.id, not externally_blocked)
            monkeypatch.setattr(task_operator, "current_time", lambda: EDITED)
            edited = tasks.set_externally_blocked(captured.id, externally_blocked)

    assert edited == replace(
        before, externally_blocked=externally_blocked, updated_at=EDITED
    )
    assert edited.externally_blocked is externally_blocked
    with SQLiteTaskStore(database) as store:
        saved = store.get(captured.id)
        assert saved == edited
        assert saved is not None
        assert saved.externally_blocked is externally_blocked
        expected_inbox = [edited] if status is TaskStatus.INBOX else []
        assert TaskOperator(store).list_inbox() == expected_inbox


@pytest.mark.parametrize("externally_blocked", [False, True])
def test_unchanged_external_flag_does_not_save_or_read_time(
    tmp_path: Path, monkeypatch: MonkeyPatch, externally_blocked: bool
) -> None:
    """Assigning the current flag value is not a meaningful change."""
    def unexpected_save(task: Task) -> None:
        """Fail if an unchanged flag edit attempts to save."""
        pytest.fail("An unchanged flag should not be saved")

    def unexpected_time() -> datetime:
        """Fail if an unchanged flag edit requests time."""
        pytest.fail("An unchanged flag should not read time")

    database = tmp_path / "heap.sqlite"
    with SQLiteTaskStore(database) as store:
        tasks = TaskOperator(store)
        captured = tasks.capture("Repair the fence")
        before = tasks.set_externally_blocked(captured.id, externally_blocked)
        monkeypatch.setattr(store, "save", unexpected_save)
        monkeypatch.setattr(task_operator, "current_time", unexpected_time)
        assert tasks.set_externally_blocked(captured.id, externally_blocked) == before

    with SQLiteTaskStore(database) as store:
        assert store.get(captured.id) == before


def test_setting_external_flag_for_missing_task_raises_key_error(tmp_path: Path) -> None:
    """Flag editing does not silently create a task for an unknown ID."""
    missing_id = uuid4()
    with SQLiteTaskStore(tmp_path / "heap.sqlite") as store:
        with pytest.raises(KeyError) as error:
            TaskOperator(store).set_externally_blocked(missing_id, True)
        assert error.value.args == (missing_id,)
        assert store.get(missing_id) is None


def test_external_flag_is_not_changed_by_dependency_or_lifecycle_operations(
    tmp_path: Path,
) -> None:
    """Adding, completing, or deleting a prerequisite never changes the manual flag."""
    database = tmp_path / "heap.sqlite"
    with SQLiteTaskStore(database) as store:
        tasks = TaskOperator(store)
        dependent = tasks.capture("Repair the fence")
        prerequisite = tasks.capture("Buy posts")
        tasks.set_externally_blocked(dependent.id, True)
        tasks.add_dependency(dependent.id, prerequisite.id)
        tasks.complete(prerequisite.id)
        tasks.delete(prerequisite.id)
        tasks.set_priority(dependent.id, Priority.P2)
        tasks.set_duration(dependent.id, Duration.THIRTY_MINUTES)
        moved = tasks.move_to_heap(dependent.id)
        assert moved.externally_blocked is True
        completed = tasks.complete(dependent.id)
        assert completed.externally_blocked is True

    with SQLiteTaskStore(database) as store:
        assert store.get(dependent.id) == completed


def test_older_tasks_gain_false_external_flag_without_losing_data(
    tmp_path: Path, monkeypatch: MonkeyPatch
) -> None:
    """Existing database rows gain the default flag and support subsequent edits."""
    database = tmp_path / "heap.sqlite"
    task_id = UUID(int=1)
    with closing(sqlite3.connect(database)) as connection:
        connection.execute(
            """
            CREATE TABLE tasks (
                id TEXT PRIMARY KEY NOT NULL,
                title TEXT NOT NULL,
                status TEXT NOT NULL,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            )
            """
        )
        connection.execute(
            "INSERT INTO tasks VALUES (?, ?, ?, ?, ?)",
            (
                str(task_id), "Repair the fence", "inbox",
                CREATED.isoformat(), CREATED.isoformat(),
            ),
        )
        connection.commit()

    before = Task(
        id=task_id, title="Repair the fence", status=TaskStatus.INBOX,
        created_at=CREATED, updated_at=CREATED,
    )
    with SQLiteTaskStore(database) as store:
        saved = store.get(task_id)
        assert saved == before
        assert saved is not None
        assert saved.externally_blocked is False
        monkeypatch.setattr(task_operator, "current_time", lambda: EDITED)
        edited = TaskOperator(store).set_externally_blocked(task_id, True)

    assert edited == replace(before, externally_blocked=True, updated_at=EDITED)
    with SQLiteTaskStore(database) as store:
        assert store.get(task_id) == edited


def test_external_flag_write_failure_leaves_saved_task_unchanged(
    tmp_path: Path, monkeypatch: MonkeyPatch
) -> None:
    """A failed flag save raises an error rather than reporting success."""
    def failed_save(task: Task) -> None:
        """Represent a write that fails before committing."""
        raise sqlite3.OperationalError("Write failed")

    database = tmp_path / "heap.sqlite"
    with SQLiteTaskStore(database) as store:
        tasks = TaskOperator(store)
        captured = tasks.capture("Repair the fence")
        monkeypatch.setattr(store, "save", failed_save)
        with pytest.raises(sqlite3.OperationalError, match="Write failed"):
            tasks.set_externally_blocked(captured.id, True)

    with SQLiteTaskStore(database) as store:
        assert store.get(captured.id) == captured
