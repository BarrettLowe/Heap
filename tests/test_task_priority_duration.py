import sqlite3
from contextlib import closing
from pathlib import Path
from uuid import UUID

import pytest

from heap.logic.duration import Duration
from heap.logic.priority import Priority
from heap.logic.task_operator import TaskOperator
from heap.persistence.sqlite_task_store import SQLiteTaskStore


# Cases: priority codes and labels; known and unknown duration buckets;
# invalid values; capture defaults; saved values survive reopening;
# databases from before these fields retain their tasks.


@pytest.mark.parametrize(
    ("priority", "code", "label"),
    [
        (Priority.P1, 1, "Critical"),
        (Priority.P2, 2, "Important"),
        (Priority.P3, 3, "Normal"),
        (Priority.P4, 4, "Someday"),
        (Priority.P5, 5, "Maybe"),
    ],
)
def test_priority_has_stable_code_and_descriptive_label(
    priority: Priority, code: int, label: str
) -> None:
    """Priority codes retain the five agreed descriptive labels."""
    assert priority.value == code
    assert priority.label == label


def test_duration_buckets_include_unknown_and_six_known_estimates() -> None:
    """Duration estimates use only the agreed buckets."""
    assert [duration.minutes for duration in Duration] == [None, 5, 15, 30, 60, 120, 240]
    assert Duration.UNKNOWN.minutes is None


@pytest.mark.parametrize("code", [0, 6])
def test_invalid_priority_code_is_rejected(code: int) -> None:
    """Values outside the five priority levels are not valid priorities."""
    with pytest.raises(ValueError):
        Priority(code)


@pytest.mark.parametrize("minutes", [-1, 0, 10, 241])
def test_non_bucket_duration_is_rejected(minutes: int) -> None:
    """Arbitrary estimates cannot become duration buckets."""
    with pytest.raises(ValueError):
        Duration(minutes)


def test_capture_leaves_priority_unset_and_duration_unknown(tmp_path: Path) -> None:
    """Title-only capture does not invent importance or a duration estimate."""
    with SQLiteTaskStore(tmp_path / "heap.sqlite") as store:
        task = TaskOperator(store).capture("Repair the fence")
        assert task.priority is None
        assert task.duration is Duration.UNKNOWN
        assert store.get(task.id) == task


@pytest.mark.parametrize("priority", list(Priority))
@pytest.mark.parametrize("duration", list(Duration))
def test_priority_and_duration_survive_database_reopen(
    tmp_path: Path, priority: Priority, duration: Duration
) -> None:
    """Explicitly saved priority and duration appear in retrieval and inbox lists."""
    database = tmp_path / "heap.sqlite"
    with SQLiteTaskStore(database) as store:
        task = TaskOperator(store).capture("Repair the fence")
        task.priority = priority
        task.duration = duration
        store.save(task)

    with SQLiteTaskStore(database) as store:
        assert store.get(task.id) == task
        assert TaskOperator(store).list_inbox() == [task]


def test_older_database_keeps_tasks_with_unset_priority_and_unknown_duration(
    tmp_path: Path,
) -> None:
    """Opening the previous schema adds fields without losing existing tasks."""
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
                "2026-01-02T12:00:00+00:00", "2026-01-02T12:00:00+00:00",
            ),
        )
        connection.commit()

    with SQLiteTaskStore(database) as store:
        task = store.get(task_id)
        assert task is not None
        assert task.title == "Repair the fence"
        assert task.priority is None
        assert task.duration is Duration.UNKNOWN
        assert task.project_id is None
        assert task.on_deck_since is None
        task.priority = Priority.P2
        task.duration = Duration.THIRTY_MINUTES
        store.save(task)

    with SQLiteTaskStore(database) as store:
        assert store.get(task_id) == task
