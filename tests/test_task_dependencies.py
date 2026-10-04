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
from heap.logic.task import Task
from heap.logic.task_operator import TaskOperator
from heap.persistence.sqlite_task_store import SQLiteTaskStore


CREATED: datetime = datetime(2026, 1, 2, 12, 0, tzinfo=UTC)
EDITED: datetime = datetime(2026, 1, 3, 12, 0, tzinfo=UTC)
REMOVED: datetime = datetime(2026, 1, 4, 12, 0, tzinfo=UTC)


@pytest.fixture
def captured_tasks(tmp_path: Path, monkeypatch: MonkeyPatch) -> list[Task]:
    """Save tasks with fixed IDs and creation time for dependency tests."""
    monkeypatch.setattr(task_operator, "current_time", lambda: CREATED)
    with SQLiteTaskStore(tmp_path / "heap.sqlite") as store:
        tasks = TaskOperator(store)
        captured: list[Task] = []
        for task_id, title in enumerate(
            ["Paint wall", "Repair drywall", "Buy paint", "Install shelves"], start=1
        ):
            with monkeypatch.context() as task_patch:
                task_patch.setattr(task_operator, "uuid4", lambda: UUID(int=task_id))
                captured.append(tasks.capture(title))
        return captured


def test_multiple_dependencies_and_shared_prerequisite_survive_reopening(
    tmp_path: Path, monkeypatch: MonkeyPatch, captured_tasks: list[Task]
) -> None:
    """Dependency links persist in ID order without changing unrelated fields."""
    paint, drywall, supplies, shelves = captured_tasks
    database = tmp_path / "heap.sqlite"
    with SQLiteTaskStore(database) as store:
        tasks = TaskOperator(store)
        tasks.set_priority(paint.id, Priority.P2)
        tasks.set_duration(paint.id, Duration.THIRTY_MINUTES)
        before = tasks.move_to_heap(paint.id)
        monkeypatch.setattr(task_operator, "current_time", lambda: EDITED)
        assert tasks.add_dependency(paint.id, supplies.id) is None
        tasks.add_dependency(paint.id, drywall.id)
        tasks.add_dependency(shelves.id, drywall.id)

    with SQLiteTaskStore(database) as store:
        tasks = TaskOperator(store)
        assert tasks.list_dependencies(paint.id) == [drywall.id, supplies.id]
        assert tasks.list_dependencies(shelves.id) == [drywall.id]
        assert tasks.list_dependencies(drywall.id) == []
        assert store.get(paint.id) == replace(before, updated_at=EDITED)
        assert store.get(shelves.id) == replace(shelves, updated_at=EDITED)
        assert store.get(drywall.id) == drywall
        assert store.get(supplies.id) == supplies
        listed = tasks.list_dependencies(paint.id)
        listed.clear()
        assert tasks.list_dependencies(paint.id) == [drywall.id, supplies.id]


def test_removing_dependency_preserves_other_links_after_reopening(
    tmp_path: Path, monkeypatch: MonkeyPatch, captured_tasks: list[Task]
) -> None:
    """Removing a link updates only its dependent task and retains other links."""
    paint, drywall, supplies, shelves = captured_tasks
    database = tmp_path / "heap.sqlite"
    with SQLiteTaskStore(database) as store:
        tasks = TaskOperator(store)
        tasks.add_dependency(paint.id, drywall.id)
        tasks.add_dependency(paint.id, supplies.id)
        tasks.add_dependency(shelves.id, drywall.id)
        monkeypatch.setattr(task_operator, "current_time", lambda: REMOVED)
        assert tasks.remove_dependency(paint.id, drywall.id) is None

    with SQLiteTaskStore(database) as store:
        tasks = TaskOperator(store)
        assert tasks.list_dependencies(paint.id) == [supplies.id]
        assert tasks.list_dependencies(shelves.id) == [drywall.id]
        assert store.get(paint.id) == replace(paint, updated_at=REMOVED)
        assert store.get(drywall.id) == drywall


def test_duplicate_add_and_absent_remove_do_not_write_or_read_time(
    tmp_path: Path, monkeypatch: MonkeyPatch, captured_tasks: list[Task]
) -> None:
    """Repeated relationship edits leave the link set and timestamps unchanged."""
    def unexpected_write(
        task_id: UUID, prerequisite_id: UUID, updated_at: datetime
    ) -> None:
        """Fail if an unchanged dependency edit reaches storage."""
        pytest.fail("An unchanged dependency should not be written")

    def unexpected_time() -> datetime:
        """Fail if an unchanged dependency edit requests time."""
        pytest.fail("An unchanged dependency should not read time")

    paint, drywall, supplies, _ = captured_tasks
    database = tmp_path / "heap.sqlite"
    with SQLiteTaskStore(database) as store:
        tasks = TaskOperator(store)
        tasks.add_dependency(paint.id, drywall.id)
        before = store.get(paint.id)
        monkeypatch.setattr(store, "add_dependency", unexpected_write)
        monkeypatch.setattr(store, "remove_dependency", unexpected_write)
        monkeypatch.setattr(task_operator, "current_time", unexpected_time)
        tasks.add_dependency(paint.id, drywall.id)
        tasks.remove_dependency(paint.id, supplies.id)

    with SQLiteTaskStore(database) as store:
        assert store.get(paint.id) == before
        assert TaskOperator(store).list_dependencies(paint.id) == [drywall.id]


@pytest.mark.parametrize("chain_length", [1, 2, 3, 4])
def test_self_dependencies_and_cycles_are_rejected_without_changes(
    tmp_path: Path, captured_tasks: list[Task], chain_length: int
) -> None:
    """Self-dependencies and cycles of different lengths leave saved links alone."""
    chain = captured_tasks[:chain_length]
    database = tmp_path / "heap.sqlite"
    with SQLiteTaskStore(database) as store:
        tasks = TaskOperator(store)
        for dependent, prerequisite in zip(chain, chain[1:]):
            tasks.add_dependency(dependent.id, prerequisite.id)
        before = [store.get(task.id) for task in chain]
        with pytest.raises(ValueError):
            tasks.add_dependency(chain[-1].id, chain[0].id)

    with SQLiteTaskStore(database) as store:
        tasks = TaskOperator(store)
        assert [store.get(task.id) for task in chain] == before
        for dependent, prerequisite in zip(chain, chain[1:]):
            assert tasks.list_dependencies(dependent.id) == [prerequisite.id]
        assert tasks.list_dependencies(chain[-1].id) == []


@pytest.mark.parametrize("operation", ["add_dependency", "remove_dependency"])
@pytest.mark.parametrize("missing_dependent", [False, True])
def test_missing_dependency_endpoints_raise_key_error(
    tmp_path: Path, captured_tasks: list[Task], operation: str, missing_dependent: bool
) -> None:
    """A relationship edit requires both tasks to exist."""
    paint, drywall, _, _ = captured_tasks
    missing_id = uuid4()
    task_id = missing_id if missing_dependent else paint.id
    prerequisite_id = drywall.id if missing_dependent else missing_id
    database = tmp_path / "heap.sqlite"
    with SQLiteTaskStore(database) as store:
        tasks = TaskOperator(store)
        with pytest.raises(KeyError) as error:
            getattr(tasks, operation)(task_id, prerequisite_id)
        assert error.value.args == (missing_id,)

    with SQLiteTaskStore(database) as store:
        assert store.get(paint.id) == paint
        assert TaskOperator(store).list_dependencies(paint.id) == []


def test_listing_dependencies_of_missing_task_raises_key_error(tmp_path: Path) -> None:
    """A missing task is distinct from an existing task with no prerequisites."""
    missing_id = uuid4()
    with SQLiteTaskStore(tmp_path / "heap.sqlite") as store:
        with pytest.raises(KeyError) as error:
            TaskOperator(store).list_dependencies(missing_id)
        assert error.value.args == (missing_id,)


@pytest.mark.parametrize("operation", ["add_dependency", "remove_dependency"])
def test_dependency_link_and_timestamp_roll_back_together(
    tmp_path: Path, captured_tasks: list[Task], operation: str
) -> None:
    """A failed timestamp write also rolls back its dependency link edit."""
    paint, drywall, _, _ = captured_tasks
    database = tmp_path / "heap.sqlite"
    with SQLiteTaskStore(database) as store:
        tasks = TaskOperator(store)
        if operation == "remove_dependency":
            tasks.add_dependency(paint.id, drywall.id)
        before = store.get(paint.id)
        links_before = tasks.list_dependencies(paint.id)

    with closing(sqlite3.connect(database)) as connection:
        connection.execute(
            """
            CREATE TRIGGER reject_timestamp_update
            BEFORE UPDATE OF updated_at ON tasks
            BEGIN
                SELECT RAISE(ABORT, 'Timestamp write failed');
            END
            """
        )
        connection.commit()

    with SQLiteTaskStore(database) as store:
        with pytest.raises(sqlite3.IntegrityError, match="Timestamp write failed"):
            getattr(TaskOperator(store), operation)(paint.id, drywall.id)

    with SQLiteTaskStore(database) as store:
        assert store.get(paint.id) == before
        assert TaskOperator(store).list_dependencies(paint.id) == links_before


def test_converging_dependency_paths_are_not_cycles(
    tmp_path: Path, captured_tasks: list[Task]
) -> None:
    """Reaching the same prerequisite through multiple paths is valid."""
    paint, drywall, supplies, shelves = captured_tasks
    database = tmp_path / "heap.sqlite"
    with SQLiteTaskStore(database) as store:
        tasks = TaskOperator(store)
        tasks.add_dependency(paint.id, drywall.id)
        tasks.add_dependency(paint.id, supplies.id)
        tasks.add_dependency(drywall.id, shelves.id)
        tasks.add_dependency(supplies.id, shelves.id)
        later = tasks.capture("Decorate room")
        tasks.add_dependency(later.id, paint.id)

    with SQLiteTaskStore(database) as store:
        assert TaskOperator(store).list_dependencies(later.id) == [paint.id]


@pytest.mark.parametrize("invalid_link", ["self", "missing_dependent", "missing_prerequisite"])
def test_database_constraints_reject_invalid_dependency_links(
    tmp_path: Path, captured_tasks: list[Task], invalid_link: str
) -> None:
    """SQLite also prevents self-links and references to missing tasks."""
    paint, drywall, _, _ = captured_tasks
    missing_id = uuid4()
    task_id = missing_id if invalid_link == "missing_dependent" else paint.id
    prerequisite_id = drywall.id
    if invalid_link == "missing_prerequisite":
        prerequisite_id = missing_id
    elif invalid_link == "self":
        prerequisite_id = paint.id
    database = tmp_path / "heap.sqlite"
    with SQLiteTaskStore(database) as store:
        with pytest.raises(sqlite3.IntegrityError):
            store.add_dependency(task_id, prerequisite_id, EDITED)

    with SQLiteTaskStore(database) as store:
        assert store.get(paint.id) == paint
        assert TaskOperator(store).list_dependencies(paint.id) == []


def test_storage_no_op_dependency_edits_leave_timestamp_unchanged(
    tmp_path: Path, captured_tasks: list[Task]
) -> None:
    """Storage duplicate adds and absent removals also preserve timestamps."""
    paint, drywall, supplies, _ = captured_tasks
    database = tmp_path / "heap.sqlite"
    with SQLiteTaskStore(database) as store:
        TaskOperator(store).add_dependency(paint.id, drywall.id)
        before = store.get(paint.id)
        store.add_dependency(paint.id, drywall.id, EDITED)
        store.remove_dependency(paint.id, supplies.id, REMOVED)

    with SQLiteTaskStore(database) as store:
        assert store.get(paint.id) == before
        assert TaskOperator(store).list_dependencies(paint.id) == [drywall.id]


def test_database_without_dependency_table_keeps_existing_tasks(
    tmp_path: Path, captured_tasks: list[Task], monkeypatch: MonkeyPatch
) -> None:
    """Opening a pre-dependency database preserves task data and adds link storage."""
    paint, drywall, _, _ = captured_tasks
    database = tmp_path / "heap.sqlite"
    with SQLiteTaskStore(database) as store:
        tasks = TaskOperator(store)
        tasks.set_priority(paint.id, Priority.P2)
        tasks.set_duration(paint.id, Duration.THIRTY_MINUTES)
        on_heap = tasks.move_to_heap(paint.id)
        completed = tasks.complete(drywall.id)

    with closing(sqlite3.connect(database)) as connection:
        connection.execute("DROP TABLE task_dependencies")
        connection.commit()

    with SQLiteTaskStore(database) as store:
        assert store.get(paint.id) == on_heap
        assert store.get(drywall.id) == completed
        monkeypatch.setattr(task_operator, "current_time", lambda: EDITED)
        TaskOperator(store).add_dependency(paint.id, drywall.id)

    with SQLiteTaskStore(database) as store:
        assert store.get(paint.id) == replace(on_heap, updated_at=EDITED)
        assert store.get(drywall.id) == completed
        assert TaskOperator(store).list_dependencies(paint.id) == [drywall.id]
