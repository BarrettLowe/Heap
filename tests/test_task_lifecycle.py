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
ON_DECK: datetime = datetime(2026, 1, 3, 12, 0, tzinfo=UTC)
COMPLETED: datetime = datetime(2026, 1, 4, 12, 0, tzinfo=UTC)


@pytest.mark.parametrize("on_deck", [False, True])
def test_completion_retains_history_after_reopening(
    tmp_path: Path, monkeypatch: MonkeyPatch, on_deck: bool
) -> None:
    """Completion retains inbox and on-deck tasks without altering their history."""
    database = tmp_path / "heap.sqlite"
    monkeypatch.setattr(task_operator, "current_time", lambda: CREATED)
    with SQLiteProjectStore(database) as project_store:
        project = ProjectOperator(project_store).create("Fence repair")
        with SQLiteTaskStore(database) as store:
            tasks = TaskOperator(store, project_store)
            untouched = tasks.capture("Buy fence posts")
            before = tasks.capture("Repair the fence")
            assert before.completed_at is None
            if on_deck:
                tasks.set_project(before.id, project.id)
                tasks.set_priority(before.id, Priority.P2)
                tasks.set_duration(before.id, Duration.THIRTY_MINUTES)
                monkeypatch.setattr(task_operator, "current_time", lambda: ON_DECK)
                before = tasks.move_to_on_deck(before.id)
            clock_reads = 0

            def completion_time() -> datetime:
                """Count time reads while providing a fixed completion time."""
                nonlocal clock_reads
                clock_reads += 1
                return COMPLETED

            monkeypatch.setattr(task_operator, "current_time", completion_time)
            completed = tasks.complete(before.id)
            assert clock_reads == 1

    assert completed == replace(
        before, status=TaskStatus.COMPLETED,
        completed_at=COMPLETED, updated_at=COMPLETED,
    )
    with SQLiteTaskStore(database) as store:
        assert store.get(before.id) == completed
        assert store.get(before.id) is not completed
        assert store.get(untouched.id) == untouched
        assert TaskOperator(store).list_inbox() == [untouched]
    with SQLiteProjectStore(database) as project_store:
        assert project_store.get(project.id) == project


def test_repeated_completion_does_not_save_or_read_time(
    tmp_path: Path, monkeypatch: MonkeyPatch
) -> None:
    """Completing a retained occurrence again preserves its original timestamps."""
    def unexpected_save(task: Task) -> None:
        """Fail if repeated completion tries to save."""
        pytest.fail("A completed task should not be saved again")

    def unexpected_time() -> datetime:
        """Fail if repeated completion requests a new timestamp."""
        pytest.fail("Repeated completion should not read time")

    database = tmp_path / "heap.sqlite"
    with SQLiteTaskStore(database) as store:
        tasks = TaskOperator(store)
        task = tasks.capture("Repair the fence")
        monkeypatch.setattr(task_operator, "current_time", lambda: COMPLETED)
        completed = tasks.complete(task.id)

    with SQLiteTaskStore(database) as store:
        monkeypatch.setattr(store, "save", unexpected_save)
        monkeypatch.setattr(task_operator, "current_time", unexpected_time)
        assert TaskOperator(store).complete(task.id) == completed

    with SQLiteTaskStore(database) as store:
        assert store.get(task.id) == completed


def test_completed_task_cannot_move_back_on_deck(
    tmp_path: Path, monkeypatch: MonkeyPatch
) -> None:
    """An organized completed task stays completed when a move is rejected."""
    database = tmp_path / "heap.sqlite"
    with SQLiteTaskStore(database) as store:
        tasks = TaskOperator(store)
        task = tasks.capture("Repair the fence")
        tasks.set_priority(task.id, Priority.P2)
        tasks.set_duration(task.id, Duration.THIRTY_MINUTES)
        tasks.move_to_on_deck(task.id)
        monkeypatch.setattr(task_operator, "current_time", lambda: COMPLETED)
        completed = tasks.complete(task.id)
        with pytest.raises(ValueError, match="completed"):
            tasks.move_to_on_deck(task.id)

    with SQLiteTaskStore(database) as store:
        assert store.get(task.id) == completed
        assert TaskOperator(store).list_inbox() == []


@pytest.mark.parametrize("state", ["inbox", "on_deck", "completed"])
def test_hard_delete_removes_only_selected_task_after_reopening(
    tmp_path: Path, state: str
) -> None:
    """Explicit deletion removes any task state without deleting related records."""
    database = tmp_path / "heap.sqlite"
    with SQLiteProjectStore(database) as project_store:
        project = ProjectOperator(project_store).create("Fence repair")
        with SQLiteTaskStore(database) as store:
            tasks = TaskOperator(store, project_store)
            untouched = tasks.capture("Buy fence posts")
            task = tasks.capture("Repair the fence")
            tasks.set_project(task.id, project.id)
            if state == "on_deck":
                tasks.set_priority(task.id, Priority.P2)
                tasks.set_duration(task.id, Duration.THIRTY_MINUTES)
                tasks.move_to_on_deck(task.id)
            elif state == "completed":
                tasks.complete(task.id)
            assert tasks.delete(task.id) is None
            assert store.get(task.id) is None
            with pytest.raises(KeyError):
                tasks.delete(task.id)

    with SQLiteTaskStore(database) as store:
        assert store.get(task.id) is None
        assert store.get(untouched.id) == untouched
        assert TaskOperator(store).list_inbox() == [untouched]
    with SQLiteProjectStore(database) as project_store:
        assert project_store.get(project.id) == project


def test_missing_task_completion_and_deletion_raise_key_error(tmp_path: Path) -> None:
    """Neither operation creates a task or silently accepts an unknown ID."""
    missing_id = uuid4()
    database = tmp_path / "heap.sqlite"
    with SQLiteTaskStore(database) as store:
        tasks = TaskOperator(store)
        with pytest.raises(KeyError) as completion_error:
            tasks.complete(missing_id)
        assert completion_error.value.args == (missing_id,)
        with pytest.raises(KeyError) as deletion_error:
            tasks.delete(missing_id)
        assert deletion_error.value.args == (missing_id,)

    with SQLiteTaskStore(database) as store:
        assert store.get(missing_id) is None
        assert TaskOperator(store).list_inbox() == []


def test_previous_schema_preserves_tasks_and_supports_completion(
    tmp_path: Path, monkeypatch: MonkeyPatch
) -> None:
    """Existing tasks gain an empty completion timestamp without losing fields."""
    database = tmp_path / "heap.sqlite"
    task_id = UUID(int=1)
    project_id = UUID(int=2)
    with closing(sqlite3.connect(database)) as connection:
        connection.execute(
            """
            CREATE TABLE tasks (
                id TEXT PRIMARY KEY NOT NULL,
                title TEXT NOT NULL,
                status TEXT NOT NULL,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                priority INTEGER,
                duration_minutes INTEGER,
                project_id TEXT,
                on_deck_since TEXT
            )
            """
        )
        connection.execute(
            "INSERT INTO tasks VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
            (
                str(task_id), "Repair the fence", "on_deck",
                CREATED.isoformat(), ON_DECK.isoformat(),
                Priority.P2.value, Duration.THIRTY_MINUTES.minutes,
                str(project_id), ON_DECK.isoformat(),
            ),
        )
        connection.commit()

    before = Task(
        id=task_id, title="Repair the fence", status=TaskStatus.ON_DECK,
        created_at=CREATED, updated_at=ON_DECK, priority=Priority.P2,
        duration=Duration.THIRTY_MINUTES, project_id=project_id,
        on_deck_since=ON_DECK,
    )
    with SQLiteTaskStore(database) as store:
        saved = store.get(task_id)
        assert saved is not None
        assert saved == before
        assert saved.completed_at is None
        monkeypatch.setattr(task_operator, "current_time", lambda: COMPLETED)
        completed = TaskOperator(store).complete(task_id)
        assert completed == replace(
            before, status=TaskStatus.COMPLETED,
            completed_at=COMPLETED, updated_at=COMPLETED,
        )

    with SQLiteTaskStore(database) as store:
        assert store.get(task_id) == completed


@pytest.mark.parametrize("operation", ["complete", "delete"])
def test_storage_failure_is_not_reported_as_success(
    tmp_path: Path, monkeypatch: MonkeyPatch, operation: str
) -> None:
    """A failed write raises an error and leaves the saved task unchanged."""
    def failed_write(value: Task | UUID) -> None:
        """Represent a storage write that fails before committing."""
        raise sqlite3.OperationalError("Write failed")

    database = tmp_path / "heap.sqlite"
    with SQLiteTaskStore(database) as store:
        tasks = TaskOperator(store)
        original = tasks.capture("Repair the fence")
        if operation == "complete":
            monkeypatch.setattr(store, "save", failed_write)
            with pytest.raises(sqlite3.OperationalError, match="Write failed"):
                tasks.complete(original.id)
        else:
            monkeypatch.setattr(store, "delete", failed_write)
            with pytest.raises(sqlite3.OperationalError, match="Write failed"):
                tasks.delete(original.id)

    with SQLiteTaskStore(database) as store:
        assert store.get(original.id) == original
        assert TaskOperator(store).list_inbox() == [original]
