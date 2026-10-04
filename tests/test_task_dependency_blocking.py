import sqlite3
from pathlib import Path
from uuid import UUID, uuid4

import pytest
from pytest import MonkeyPatch

from heap.logic import task_operator
from heap.logic.duration import Duration
from heap.logic.priority import Priority
from heap.logic.task import TaskStatus
from heap.logic.task_operator import TaskOperator
from heap.persistence import sqlite_task_store
from heap.persistence.sqlite_task_store import SQLiteTaskStore


@pytest.fixture
def sql_statements(monkeypatch: MonkeyPatch) -> list[str]:
    """Trace SQLite statements so tests can check the number of database calls."""
    statements: list[str] = []
    original_connect = sqlite3.connect

    def traced_connect(database: Path) -> sqlite3.Connection:
        """Attach a trace callback to each connection opened by the task store."""
        connection = original_connect(database)
        connection.set_trace_callback(statements.append)
        return connection

    monkeypatch.setattr(sqlite_task_store.sqlite3, "connect", traced_connect)
    return statements


@pytest.mark.parametrize(
    "prerequisite_status", [TaskStatus.INBOX, TaskStatus.ON_HEAP, TaskStatus.COMPLETED]
)
def test_single_task_blocking_uses_current_prerequisite_status_after_reopening(
    tmp_path: Path, prerequisite_status: TaskStatus
) -> None:
    """Inbox and heap prerequisites block; completed prerequisites do not."""
    database = tmp_path / "heap.sqlite"
    with SQLiteTaskStore(database) as store:
        tasks = TaskOperator(store)
        dependent = tasks.capture("Paint wall")
        prerequisite = tasks.capture("Repair drywall")
        tasks.add_dependency(dependent.id, prerequisite.id)
        if prerequisite_status is TaskStatus.ON_HEAP:
            tasks.set_priority(prerequisite.id, Priority.P2)
            tasks.set_duration(prerequisite.id, Duration.THIRTY_MINUTES)
            tasks.move_to_heap(prerequisite.id)
        elif prerequisite_status is TaskStatus.COMPLETED:
            tasks.complete(prerequisite.id)

    with SQLiteTaskStore(database) as store:
        expected = prerequisite_status is not TaskStatus.COMPLETED
        assert TaskOperator(store).is_dependency_blocked(dependent.id) is expected


@pytest.mark.parametrize("action", ["complete", "remove", "delete"])
def test_resolving_one_prerequisite_keeps_other_unfinished_prerequisites_blocking(
    tmp_path: Path, action: str
) -> None:
    """Every unfinished direct prerequisite must be resolved before blocking clears."""
    database = tmp_path / "heap.sqlite"
    with SQLiteTaskStore(database) as store:
        tasks = TaskOperator(store)
        dependent = tasks.capture("Paint wall")
        first = tasks.capture("Repair drywall")
        second = tasks.capture("Buy paint")
        tasks.add_dependency(dependent.id, first.id)
        tasks.add_dependency(dependent.id, second.id)
        assert tasks.is_dependency_blocked(dependent.id) is True
        if action == "complete":
            tasks.complete(first.id)
        elif action == "remove":
            tasks.remove_dependency(dependent.id, first.id)
        else:
            tasks.delete(first.id)
        assert tasks.is_dependency_blocked(dependent.id) is True
        tasks.complete(second.id)

    with SQLiteTaskStore(database) as store:
        assert TaskOperator(store).is_dependency_blocked(dependent.id) is False


def test_blocking_ignores_external_flag_and_does_not_filter_task_states(
    tmp_path: Path, monkeypatch: MonkeyPatch
) -> None:
    """Blocking is a read-only dependency fact, not a task eligibility decision."""
    def unexpected_time() -> None:
        """Fail if checking dependency state requests a timestamp."""
        pytest.fail("Dependency reads should not request time")

    database = tmp_path / "heap.sqlite"
    with SQLiteTaskStore(database) as store:
        tasks = TaskOperator(store)
        standalone = tasks.capture("Buy fence posts")
        dependent = tasks.capture("Paint wall")
        prerequisite = tasks.capture("Repair drywall")
        tasks.set_externally_blocked(standalone.id, True)
        tasks.add_dependency(dependent.id, prerequisite.id)
        tasks.complete(dependent.id)
        before = [store.get(task.id) for task in (standalone, dependent, prerequisite)]
        monkeypatch.setattr(task_operator, "current_time", unexpected_time)
        assert tasks.get_dependency_blocking([standalone.id, dependent.id]) == {
            standalone.id: False, dependent.id: True,
        }
        after = [store.get(task.id) for task in (standalone, dependent, prerequisite)]
        assert after == before


def test_only_direct_prerequisites_determine_blocking(tmp_path: Path) -> None:
    """An unfinished indirect prerequisite does not override a completed direct one."""
    database = tmp_path / "heap.sqlite"
    with SQLiteTaskStore(database) as store:
        tasks = TaskOperator(store)
        first = tasks.capture("Paint wall")
        second = tasks.capture("Repair drywall")
        third = tasks.capture("Buy repair supplies")
        tasks.add_dependency(first.id, second.id)
        tasks.add_dependency(second.id, third.id)
        tasks.complete(second.id)
        assert tasks.get_dependency_blocking([first.id, second.id, third.id]) == {
            first.id: False, second.id: True, third.id: False,
        }


@pytest.mark.parametrize("batch_size", [1, 100])
def test_blocking_for_multiple_tasks_uses_one_query_after_reopening(
    tmp_path: Path, sql_statements: list[str], batch_size: int
) -> None:
    """A single check or a 100-task view uses 1 query, including mixed dependency sets."""
    database = tmp_path / "heap.sqlite"
    with SQLiteTaskStore(database) as store:
        tasks = TaskOperator(store)
        unfinished = tasks.capture("Repair drywall")
        completed = tasks.capture("Buy paint")
        tasks.complete(completed.id)
        task_ids: list[UUID] = []
        expected: dict[UUID, bool] = {}
        for index in range(batch_size):
            task = tasks.capture(f"Paint section {index}")
            task_ids.append(task.id)
            # Alternate mixed, completed-only, and empty prerequisite sets.
            if index % 3 == 0:
                tasks.add_dependency(task.id, unfinished.id)
                tasks.add_dependency(task.id, completed.id)
            elif index % 3 == 1:
                tasks.add_dependency(task.id, completed.id)
            expected[task.id] = index % 3 == 0

    with SQLiteTaskStore(database) as store:
        tasks = TaskOperator(store)
        sql_statements.clear()
        if batch_size == 1:
            assert tasks.is_dependency_blocked(task_ids[0]) is expected[task_ids[0]]
        else:
            assert tasks.get_dependency_blocking(task_ids) == expected
        assert len(sql_statements) == 1
        assert sql_statements[0].lstrip().upper().startswith("SELECT")


def test_empty_batch_returns_empty_mapping_without_querying(
    tmp_path: Path, sql_statements: list[str]
) -> None:
    """An empty lookup neither reads tasks nor creates an invalid SQL IN clause."""
    with SQLiteTaskStore(tmp_path / "heap.sqlite") as store:
        sql_statements.clear()
        assert TaskOperator(store).get_dependency_blocking([]) == {}
        assert sql_statements == []


def test_duplicate_ids_return_one_result_each_without_changing_input(
    tmp_path: Path, sql_statements: list[str]
) -> None:
    """Repeated IDs do not add queries, duplicate results, or mutate the request."""
    with SQLiteTaskStore(tmp_path / "heap.sqlite") as store:
        tasks = TaskOperator(store)
        first = tasks.capture("Paint wall")
        second = tasks.capture("Repair drywall")
        tasks.add_dependency(first.id, second.id)
        requested = [second.id, first.id, second.id, first.id]
        original = requested.copy()
        sql_statements.clear()
        result = tasks.get_dependency_blocking(requested)
        assert result == {first.id: True, second.id: False}
        assert requested == original
        assert len(sql_statements) == 1
        result.clear()
        assert tasks.get_dependency_blocking(requested) == {first.id: True, second.id: False}


@pytest.mark.parametrize("missing_position", [0, 1, 2])
def test_missing_task_in_bulk_lookup_raises_key_error_with_one_query(
    tmp_path: Path, sql_statements: list[str], missing_position: int
) -> None:
    """A missing ID aborts the lookup instead of being reported as unblocked."""
    with SQLiteTaskStore(tmp_path / "heap.sqlite") as store:
        tasks = TaskOperator(store)
        first = tasks.capture("Paint wall")
        second = tasks.capture("Repair drywall")
        missing_id = uuid4()
        task_ids = [first.id, second.id]
        task_ids.insert(missing_position, missing_id)
        sql_statements.clear()
        with pytest.raises(KeyError) as error:
            tasks.get_dependency_blocking(task_ids)
        assert error.value.args == (missing_id,)
        assert len(sql_statements) == 1


def test_missing_single_task_raises_key_error_with_one_query(
    tmp_path: Path, sql_statements: list[str]
) -> None:
    """The single-task method uses the bulk lookup's missing-ID behavior."""
    missing_id = uuid4()
    with SQLiteTaskStore(tmp_path / "heap.sqlite") as store:
        sql_statements.clear()
        with pytest.raises(KeyError) as error:
            TaskOperator(store).is_dependency_blocked(missing_id)
        assert error.value.args == (missing_id,)
        assert len(sql_statements) == 1


def test_bulk_lookup_rejects_first_missing_id_in_input_order(tmp_path: Path) -> None:
    """Multiple missing IDs yield a predictable error for the first requested one."""
    first_missing = uuid4()
    second_missing = uuid4()
    with SQLiteTaskStore(tmp_path / "heap.sqlite") as store:
        with pytest.raises(KeyError) as error:
            TaskOperator(store).get_dependency_blocking([first_missing, second_missing])
        assert error.value.args == (first_missing,)
