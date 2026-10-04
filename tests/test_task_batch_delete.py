import sqlite3
from contextlib import closing
from datetime import UTC, datetime
from pathlib import Path
from uuid import uuid4

import pytest
from pytest import MonkeyPatch

from heap.logic import task_operator
from heap.logic.duration import Duration
from heap.logic.priority import Priority
from heap.logic.project import Project
from heap.logic.project_operator import ProjectOperator
from heap.logic.task import Task, TaskStatus
from heap.logic.task_operator import TaskOperator
from heap.persistence.sqlite_project_store import SQLiteProjectStore
from heap.persistence.sqlite_task_store import SQLiteTaskStore


# Distinct times expose accidental timestamp changes during link cleanup.
CREATED: datetime = datetime(2026, 1, 2, 12, 0, tzinfo=UTC)
LINKED: datetime = datetime(2026, 1, 3, 12, 0, tzinfo=UTC)
DELETED: datetime = datetime(2026, 1, 4, 12, 0, tzinfo=UTC)


@pytest.fixture
def saved_graph(
    tmp_path: Path, monkeypatch: MonkeyPatch
) -> tuple[dict[str, Task], list[Project]]:
    """Save mixed task states and links touching targets in both directions."""
    monkeypatch.setattr(task_operator, "current_time", lambda: CREATED)
    database = tmp_path / "heap.sqlite"
    with SQLiteProjectStore(database) as project_store:
        projects = ProjectOperator(project_store)
        related = projects.create("Fence repair")
        unrelated = projects.create("Garden maintenance")
        with SQLiteTaskStore(database) as store:
            tasks = TaskOperator(store, project_store)
            snapshots = {
                name: tasks.capture(name)
                for name in (
                    "inbox", "on_heap", "completed",
                    "dependent", "prerequisite", "unrelated",
                )
            }
            tasks.set_project(snapshots["inbox"].id, related.id)
            tasks.set_project(snapshots["dependent"].id, related.id)
            tasks.set_project(snapshots["unrelated"].id, unrelated.id)
            on_heap_id = snapshots["on_heap"].id
            tasks.set_priority(on_heap_id, Priority.P2)
            tasks.set_duration(on_heap_id, Duration.THIRTY_MINUTES)
            tasks.move_to_heap(on_heap_id)
            tasks.complete(snapshots["completed"].id)
            monkeypatch.setattr(task_operator, "current_time", lambda: LINKED)
            for dependent, prerequisite in (
                ("inbox", "prerequisite"),
                ("on_heap", "inbox"),
                ("completed", "on_heap"),
                ("dependent", "completed"),
                ("dependent", "prerequisite"),
                ("unrelated", "prerequisite"),
            ):
                tasks.add_dependency(snapshots[dependent].id, snapshots[prerequisite].id)
            for name, snapshot in snapshots.items():
                saved = store.get(snapshot.id)
                assert saved is not None
                snapshots[name] = saved
    monkeypatch.setattr(task_operator, "current_time", lambda: DELETED)
    return snapshots, [related, unrelated]


def assert_graph_unchanged(
    database: Path, snapshots: dict[str, Task], projects: list[Project]
) -> None:
    """Reopen storage and verify every task, dependency, and project survived."""
    expected_links = {
        "inbox": [snapshots["prerequisite"].id],
        "on_heap": [snapshots["inbox"].id],
        "completed": [snapshots["on_heap"].id],
        "dependent": sorted([
            snapshots["completed"].id, snapshots["prerequisite"].id,
        ]),
        "prerequisite": [],
        "unrelated": [snapshots["prerequisite"].id],
    }
    with SQLiteTaskStore(database) as store:
        tasks = TaskOperator(store)
        for name, snapshot in snapshots.items():
            assert store.get(snapshot.id) == snapshot
            assert tasks.list_dependencies(snapshot.id) == expected_links[name]
    with SQLiteProjectStore(database) as project_store:
        for project in projects:
            assert project_store.get(project.id) == project


def test_batch_deletion_cleans_links_and_preserves_survivors_after_reopening(
    tmp_path: Path, saved_graph: tuple[dict[str, Task], list[Project]]
) -> None:
    """Deleting mixed states removes touching edges, not unrelated data."""
    snapshots, projects = saved_graph
    targets = [snapshots[name] for name in ("inbox", "on_heap", "completed")]
    assert [target.status for target in targets] == [
        TaskStatus.INBOX, TaskStatus.ON_HEAP, TaskStatus.COMPLETED,
    ]
    database = tmp_path / "heap.sqlite"
    with SQLiteTaskStore(database) as store:
        assert TaskOperator(store).delete_many([target.id for target in targets]) is None

    with SQLiteTaskStore(database) as store:
        tasks = TaskOperator(store)
        for target in targets:
            assert store.get(target.id) is None
        for name in ("dependent", "prerequisite", "unrelated"):
            survivor = snapshots[name]
            assert store.get(survivor.id) == survivor
            expected = [] if name == "prerequisite" else [snapshots["prerequisite"].id]
            assert tasks.list_dependencies(survivor.id) == expected
    with SQLiteProjectStore(database) as project_store:
        for project in projects:
            assert project_store.get(project.id) == project


def test_single_deletion_cleans_incoming_and_outgoing_links_after_reopening(
    tmp_path: Path, saved_graph: tuple[dict[str, Task], list[Project]]
) -> None:
    """Single deletion also removes links in both directions without editing survivors."""
    snapshots, projects = saved_graph
    database = tmp_path / "heap.sqlite"
    target = snapshots["inbox"]
    with SQLiteTaskStore(database) as store:
        assert TaskOperator(store).delete(target.id) is None
    with SQLiteTaskStore(database) as store:
        tasks = TaskOperator(store)
        assert store.get(target.id) is None
        for name, snapshot in snapshots.items():
            if name != "inbox":
                assert store.get(snapshot.id) == snapshot
        assert tasks.list_dependencies(snapshots["on_heap"].id) == []
        assert tasks.list_dependencies(snapshots["prerequisite"].id) == []
        assert tasks.list_dependencies(snapshots["completed"].id) == [snapshots["on_heap"].id]
        assert tasks.list_dependencies(snapshots["dependent"].id) == sorted([
            snapshots["completed"].id, snapshots["prerequisite"].id,
        ])
        assert tasks.list_dependencies(snapshots["unrelated"].id) == [snapshots["prerequisite"].id]
    with SQLiteProjectStore(database) as project_store:
        for project in projects:
            assert project_store.get(project.id) == project


# Place the missing ID before, between, and after existing targets.
@pytest.mark.parametrize("missing_position", [0, 1, 2])
def test_missing_id_rolls_back_all_task_and_link_deletions(
    tmp_path: Path,
    saved_graph: tuple[dict[str, Task], list[Project]],
    missing_position: int,
) -> None:
    """An unknown ID aborts the whole batch regardless of its position."""
    snapshots, projects = saved_graph
    missing_id = uuid4()
    task_ids = [snapshots["inbox"].id, snapshots["completed"].id]
    task_ids.insert(missing_position, missing_id)
    database = tmp_path / "heap.sqlite"
    with SQLiteTaskStore(database) as store:
        with pytest.raises(KeyError) as error:
            TaskOperator(store).delete_many(task_ids)
        assert error.value.args == (missing_id,)
    assert_graph_unchanged(database, snapshots, projects)


def test_later_sql_failure_rolls_back_prior_deletions_and_link_cleanup(
    tmp_path: Path, saved_graph: tuple[dict[str, Task], list[Project]]
) -> None:
    """A real SQLite failure restores earlier deleted tasks and cascaded links."""
    snapshots, projects = saved_graph
    database = tmp_path / "heap.sqlite"
    first_id = snapshots["inbox"].id
    later_id = snapshots["completed"].id
    with closing(sqlite3.connect(database)) as connection:
        connection.execute(
            f"""
            CREATE TRIGGER fail_later_deletion BEFORE DELETE ON tasks
            WHEN OLD.id IN ('{first_id}', '{later_id}')
                AND NOT EXISTS (
                    SELECT id FROM tasks
                    WHERE id IN ('{first_id}', '{later_id}') AND id != OLD.id
                )
            BEGIN
                SELECT RAISE(ABORT, 'later deletion failed');
            END
            """
        )
        connection.commit()
    with SQLiteTaskStore(database) as store:
        with pytest.raises(sqlite3.IntegrityError, match="later deletion failed"):
            TaskOperator(store).delete_many([first_id, later_id])
    assert_graph_unchanged(database, snapshots, projects)


def test_empty_batch_preserves_existing_tasks_links_and_projects(
    tmp_path: Path, saved_graph: tuple[dict[str, Task], list[Project]]
) -> None:
    """An empty request leaves a populated database unchanged."""
    snapshots, projects = saved_graph
    database = tmp_path / "heap.sqlite"
    with SQLiteTaskStore(database) as store:
        assert TaskOperator(store).delete_many([]) is None
    assert_graph_unchanged(database, snapshots, projects)


def test_empty_batch_is_valid_in_an_empty_database(tmp_path: Path) -> None:
    """An empty request succeeds even when no tasks exist."""
    database = tmp_path / "heap.sqlite"
    with SQLiteTaskStore(database) as store:
        assert TaskOperator(store).delete_many([]) is None
    with SQLiteTaskStore(database) as store:
        assert TaskOperator(store).list_inbox() == []


def test_duplicate_ids_are_deleted_once_without_rejecting_the_batch(
    tmp_path: Path, saved_graph: tuple[dict[str, Task], list[Project]]
) -> None:
    """Repeated IDs do not become missing-ID errors after their first deletion."""
    snapshots, _ = saved_graph
    database = tmp_path / "heap.sqlite"
    inbox_id = snapshots["inbox"].id
    completed_id = snapshots["completed"].id
    with SQLiteTaskStore(database) as store:
        assert TaskOperator(store).delete_many([
            inbox_id, completed_id, inbox_id, completed_id,
        ]) is None
    with SQLiteTaskStore(database) as store:
        tasks = TaskOperator(store)
        assert store.get(inbox_id) is None
        assert store.get(completed_id) is None
        for name in ("on_heap", "dependent", "prerequisite", "unrelated"):
            assert store.get(snapshots[name].id) == snapshots[name]
        assert tasks.list_dependencies(snapshots["on_heap"].id) == []
        assert tasks.list_dependencies(snapshots["dependent"].id) == [snapshots["prerequisite"].id]
