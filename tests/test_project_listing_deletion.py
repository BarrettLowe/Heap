from __future__ import annotations

import sqlite3
from datetime import UTC, datetime
from pathlib import Path
from uuid import UUID

import pytest
from pytest import MonkeyPatch

from heap.logic import project_operator, task_operator
from heap.logic.duration import Duration
from heap.logic.priority import Priority
from heap.logic.project_operator import ProjectOperator
from heap.logic.task_operator import TaskOperator
from heap.persistence.sqlite_project_store import SQLiteProjectStore
from heap.persistence.sqlite_task_store import SQLiteTaskStore

CREATED = datetime(2026, 7, 1, 12, tzinfo=UTC)
EDITED = datetime(2026, 7, 2, 12, tzinfo=UTC)


def test_project_list_is_case_insensitive_and_stable(
    tmp_path: Path,
    monkeypatch: MonkeyPatch,
) -> None:
    """Project listing sorts names without changing stored snapshots."""
    monkeypatch.setattr(project_operator, "current_time", lambda: CREATED)
    with SQLiteProjectStore(tmp_path / "heap.sqlite") as store:
        projects = ProjectOperator(store)
        zulu = projects.create("zulu")
        alpha_upper = projects.create("Alpha")
        alpha_lower = projects.create("alpha")
        assert projects.list_all() == [alpha_upper, alpha_lower, zulu]


def test_project_update_replaces_fields_once_and_noop_does_not_read_time(
    tmp_path: Path,
    monkeypatch: MonkeyPatch,
) -> None:
    """Project name/description replacement uses one timestamp and one save."""
    database = tmp_path / "heap.sqlite"
    monkeypatch.setattr(project_operator, "current_time", lambda: CREATED)
    with SQLiteProjectStore(database) as store:
        projects = ProjectOperator(store)
        original = projects.create(" Fence ", "Old description")
        reads = 0
        real_save = store.save

        def clock() -> datetime:
            """Count update time reads."""
            nonlocal reads
            reads += 1
            return EDITED

        def save(project) -> None:
            """Persist an updated project and count the save."""
            nonlocal saves
            saves += 1
            real_save(project)

        saves = 0
        monkeypatch.setattr(project_operator, "current_time", clock)
        monkeypatch.setattr(store, "save", save)
        updated = projects.update(original.id, "Fence", None)
        assert updated.name == "Fence"
        assert updated.description is None
        assert updated.updated_at == EDITED
        assert reads == saves == 1

        def unexpected_time() -> datetime:
            """Fail if a no-op project update reads time."""
            pytest.fail("No-op project update read time")

        monkeypatch.setattr(project_operator, "current_time", unexpected_time)
        assert projects.update(original.id, "Fence", None) == updated
        assert reads == saves == 1
    with SQLiteProjectStore(database) as store:
        assert ProjectOperator(store).get(original.id) == updated


def test_project_view_includes_all_assigned_task_states_in_stable_order(
    tmp_path: Path,
    monkeypatch: MonkeyPatch,
) -> None:
    """Project task listing includes unfinished and completed snapshots."""
    database = tmp_path / "heap.sqlite"
    monkeypatch.setattr(project_operator, "current_time", lambda: CREATED)
    monkeypatch.setattr(task_operator, "current_time", lambda: CREATED)
    with SQLiteProjectStore(database) as project_store:
        project = ProjectOperator(project_store).create("Fence")
        with SQLiteTaskStore(database) as task_store:
            tasks = TaskOperator(task_store, project_store)
            first = tasks.capture("First")
            second = tasks.capture("Second")
            other = tasks.capture("Other")
            first.project_id = second.project_id = project.id
            task_store.save_many([first, second])
            tasks.set_priority(second.id, Priority.P1)
            tasks.set_duration(second.id, Duration.THIRTY_MINUTES)
            tasks.complete(second.id)
            completed = task_store.get(second.id)
            assert completed is not None
            expected = sorted(
                [first, completed], key=lambda task: (task.created_at, task.id)
            )
            assert tasks.list_for_project(project.id) == expected
            with pytest.raises(KeyError):
                tasks.list_for_project(UUID(int=99))
            assert tasks.list_for_project(project.id) == expected
            assert task_store.get(other.id) == other


def test_deleting_project_atomically_removes_all_tasks_and_links_after_reopen(
    tmp_path: Path,
    monkeypatch: MonkeyPatch,
) -> None:
    """Project deletion removes all assigned task states and touching links."""
    database = tmp_path / "heap.sqlite"
    monkeypatch.setattr(project_operator, "current_time", lambda: CREATED)
    with SQLiteProjectStore(database) as project_store:
        projects = ProjectOperator(project_store)
        doomed = projects.create("Doomed")
        survivor = projects.create("Survivor")
        with SQLiteTaskStore(database) as task_store:
            tasks = TaskOperator(task_store, project_store)
            assigned = tasks.capture("Assigned")
            completed = tasks.capture("Assigned and completed")
            outside = tasks.capture("Outside")
            assigned.project_id = completed.project_id = doomed.id
            outside.project_id = survivor.id
            task_store.save_many([assigned, completed, outside])
            tasks.set_priority(completed.id, Priority.P2)
            tasks.set_duration(completed.id, Duration.THIRTY_MINUTES)
            tasks.complete(completed.id)
            tasks.add_dependency(outside.id, assigned.id)
            outside = task_store.get(outside.id)
            assert outside is not None
            assert projects.delete(doomed.id) is None
            assert projects.get(doomed.id) is None
            assert projects.get(survivor.id) == survivor
            assert task_store.get(assigned.id) is None
            assert task_store.get(completed.id) is None
            assert task_store.get(outside.id) == outside
            assert task_store.list_dependencies(outside.id) == []
            with pytest.raises(KeyError):
                projects.delete(doomed.id)
    with SQLiteProjectStore(database) as project_store:
        assert ProjectOperator(project_store).list_all() == [survivor]
        with SQLiteTaskStore(database) as task_store:
            assert task_store.get(assigned.id) is None
            assert task_store.get(completed.id) is None
            assert task_store.get(outside.id) == outside
            assert task_store.list_dependencies(outside.id) == []


def test_failed_project_cascade_rolls_back_project_tasks_and_links(
    tmp_path: Path,
    monkeypatch: MonkeyPatch,
) -> None:
    """A task deletion failure rolls back the project and all prior deletions."""
    database = tmp_path / "heap.sqlite"
    monkeypatch.setattr(project_operator, "current_time", lambda: CREATED)
    with SQLiteProjectStore(database) as project_store:
        project = ProjectOperator(project_store).create("Doomed")
        other = ProjectOperator(project_store).create("Other")
        with SQLiteTaskStore(database) as task_store:
            tasks = TaskOperator(task_store, project_store)
            assigned = tasks.capture("Assigned")
            outside = tasks.capture("Outside")
            assigned.project_id = project.id
            task_store.save(assigned)
            tasks.add_dependency(outside.id, assigned.id)
            outside = task_store.get(outside.id)
            assert outside is not None
    with sqlite3.connect(database) as connection:
        connection.execute(
            """CREATE TRIGGER reject_project_task_delete BEFORE DELETE ON tasks
            WHEN OLD.project_id IS NOT NULL
            BEGIN SELECT RAISE(ABORT, 'project task delete failed'); END"""
        )
        connection.commit()
    with (
        SQLiteProjectStore(database) as project_store,
        pytest.raises(sqlite3.IntegrityError, match="project task delete failed"),
    ):
        ProjectOperator(project_store).delete(project.id)
    with SQLiteProjectStore(database) as project_store:
        assert ProjectOperator(project_store).get(project.id) == project
        assert ProjectOperator(project_store).get(other.id) == other
        with SQLiteTaskStore(database) as task_store:
            assert task_store.get(assigned.id) == assigned
            assert task_store.get(outside.id) == outside
            assert task_store.list_dependencies(outside.id) == [assigned.id]
