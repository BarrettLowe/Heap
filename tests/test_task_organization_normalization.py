from __future__ import annotations

import sqlite3
from dataclasses import replace
from datetime import UTC, datetime
from pathlib import Path
from uuid import UUID, uuid4

import pytest
from fastapi.testclient import TestClient
from pytest import MonkeyPatch

from heap.interface.app import create_app
from heap.logic import task_operator
from heap.logic.duration import Duration
from heap.logic.priority import Priority
from heap.logic.task import Task, TaskStatus
from heap.logic.task_operator import TaskOperator
from heap.persistence.sqlite_task_store import SQLiteTaskStore

CREATED = datetime(2026, 1, 2, 12, 0, tzinfo=UTC)
NORMALIZED = datetime(2026, 1, 5, 12, 0, tzinfo=UTC)


def legacy_tasks(database: Path) -> list[Task]:
    """Save mixed legacy snapshots plus a dependency without normalizing them."""
    base = Task(
        id=UUID(int=1),
        title="Legacy ready",
        status=TaskStatus.INBOX,
        created_at=CREATED,
        updated_at=CREATED,
        priority=Priority.P2,
        duration=Duration.ONE_HOUR,
        project_id=uuid4(),
    )
    snapshots = [
        base,
        replace(base, id=UUID(int=2), externally_blocked=True),
        replace(base, id=UUID(int=3), priority=None),
        replace(base, id=UUID(int=4), status=TaskStatus.ON_HEAP, on_heap_since=CREATED),
        replace(
            base,
            id=UUID(int=5),
            status=TaskStatus.COMPLETED,
            completed_at=CREATED,
            on_heap_since=CREATED,
        ),
    ]
    with SQLiteTaskStore(database) as store:
        for task in snapshots:
            store.save(task)
        store.add_dependency(base.id, snapshots[2].id, CREATED)
    return snapshots


def test_startup_normalizes_legacy_ready_inbox_atomically_before_health(
    tmp_path: Path,
    monkeypatch: MonkeyPatch,
) -> None:
    """Startup uses one actual instant and preserves mixed data and links."""
    database = tmp_path / "heap.sqlite"
    before = legacy_tasks(database)
    reads = 0
    batches: list[list[Task]] = []
    real_save_many = SQLiteTaskStore.save_many

    def read_time() -> datetime:
        """Count startup clock reads."""
        nonlocal reads
        reads += 1
        return NORMALIZED

    def record_batch(store: SQLiteTaskStore, tasks: list[Task]) -> None:
        """Record the single normalization batch and persist it."""
        batches.append(tasks)
        real_save_many(store, tasks)

    monkeypatch.setattr(task_operator, "current_time", read_time)
    monkeypatch.setattr(SQLiteTaskStore, "save_many", record_batch)
    with TestClient(create_app(database, [])) as client:
        assert client.get("/healthz").json() == {"status": "ok"}
        on_heap = client.get("/api/v1/heap").json()["items"]
        assert len(on_heap) == 3
        by_id = {item["id"]: item for item in on_heap}
        for legacy in before[:2]:
            assert legacy.status is TaskStatus.INBOX
            assert legacy.on_heap_since is None
            normalized = by_id[str(legacy.id)]
            assert normalized["status"] == "on_heap"
            assert normalized["on_heap_since"] == "2026-01-05T12:00:00.000000Z"
            assert normalized["updated_at"] == "2026-01-05T12:00:00.000000Z"
            assert normalized["externally_blocked"] is legacy.externally_blocked
            detail = client.get(f"/api/v1/tasks/{legacy.id}")
            assert detail.status_code == 200
            assert detail.json() == normalized
        assert reads == 1
        assert len(batches) == 1
        assert {task.id for task in batches[0]} == {before[0].id, before[1].id}
    with TestClient(create_app(database, [])) as client:
        assert client.get("/healthz").status_code == 200
        assert reads == 1
        assert len(batches) == 1
    with SQLiteTaskStore(database) as store:
        for task in before[:2]:
            assert store.get(task.id) == replace(
                task,
                status=TaskStatus.ON_HEAP,
                on_heap_since=NORMALIZED,
                updated_at=NORMALIZED,
            )
        for task in before[2:]:
            assert store.get(task.id) == task
        assert store.list_dependencies(before[0].id) == [before[2].id]
        assert TaskOperator(store).normalize_organization() == 0
        assert reads == 1
        assert len(batches) == 1


def test_normalization_returns_count_and_is_idempotent_without_time_or_write(
    tmp_path: Path,
    monkeypatch: MonkeyPatch,
) -> None:
    """An explicit normalization reports count only after persistence."""
    database = tmp_path / "heap.sqlite"
    legacy_tasks(database)
    monkeypatch.setattr(task_operator, "current_time", lambda: NORMALIZED)
    with SQLiteTaskStore(database) as store:
        tasks = TaskOperator(store)
        assert tasks.normalize_organization() == 2

        def unexpected_time() -> datetime:
            """Fail if a no-op normalization reads time."""
            pytest.fail("No-op normalization read time")

        def unexpected_batch(tasks: list[Task]) -> None:
            """Fail if a no-op normalization saves."""
            pytest.fail("No-op normalization saved")

        monkeypatch.setattr(task_operator, "current_time", unexpected_time)
        monkeypatch.setattr(store, "save_many", unexpected_batch)
        assert tasks.normalize_organization() == 0


def test_later_normalization_failure_rolls_back_batch_and_aborts_startup(
    tmp_path: Path,
    monkeypatch: MonkeyPatch,
) -> None:
    """A later failed row rolls back earlier rows and prevents healthy startup."""
    database = tmp_path / "heap.sqlite"
    before = legacy_tasks(database)
    with sqlite3.connect(database) as connection:
        connection.execute(f"""
            CREATE TRIGGER fail_later BEFORE UPDATE ON tasks
            WHEN OLD.id = '{before[1].id}'
            BEGIN SELECT RAISE(ABORT, 'later row failed'); END
        """)
    monkeypatch.setattr(task_operator, "current_time", lambda: NORMALIZED)
    with (
        pytest.raises(sqlite3.IntegrityError, match="later row failed"),
        TestClient(create_app(database, [])),
    ):
        pytest.fail("Startup unexpectedly succeeded")
    with SQLiteTaskStore(database) as store:
        for task in before:
            assert store.get(task.id) == task
        assert store.list_dependencies(before[0].id) == [before[2].id]


def test_save_many_empty_batch_does_not_write_and_failure_rolls_back_insert_and_update(
    tmp_path: Path,
) -> None:
    """Batch persistence is all-or-nothing for both new and existing snapshots."""
    database = tmp_path / "heap.sqlite"
    before = legacy_tasks(database)
    with sqlite3.connect(database) as connection:
        connection.execute(f"""
            CREATE TRIGGER fail_update BEFORE UPDATE ON tasks
            WHEN OLD.id = '{before[1].id}'
            BEGIN SELECT RAISE(ABORT, 'batch failed'); END
        """)
    new = replace(before[0], id=uuid4())
    with SQLiteTaskStore(database) as store:
        store.save_many([])
        with pytest.raises(sqlite3.IntegrityError, match="batch failed"):
            store.save_many([new, replace(before[0], title="Changed"), before[1]])
        assert store.get(new.id) is None
        assert store.get(before[0].id) == before[0]
    with SQLiteTaskStore(database) as store:
        assert store.get(new.id) is None
        assert store.get(before[0].id) == before[0]
