from __future__ import annotations

import json
from datetime import UTC, date, datetime, timedelta
from pathlib import Path
from uuid import UUID

import pytest

from heap.logic.duration import Duration
from heap.logic.priority import Priority
from heap.logic.task import Task, TaskStatus
from heap.logic.task_ranking import rank_heap_tasks

NOW = datetime(2026, 1, 1, tzinfo=UTC)


def make_task(
    task_id: int,
    priority: Priority,
    due_date: date | None = None,
    age_days: int = 0,
    externally_blocked: bool = False,
) -> Task:
    """Build an already-qualifying Heap snapshot."""
    return Task(
        id=UUID(int=task_id),
        title=f"Task {task_id}",
        status=TaskStatus.ON_HEAP,
        created_at=NOW - timedelta(days=100),
        updated_at=NOW,
        priority=priority,
        duration=Duration.THIRTY_MINUTES,
        on_heap_since=NOW - timedelta(days=age_days),
        externally_blocked=externally_blocked,
        due_date=due_date,
    )


def test_shared_fixture_orders_tasks_for_both_local_dates() -> None:
    """The implementation agrees with the shared cross-date contract fixture."""
    fixture_path = Path(__file__).parents[1] / "docs" / "heap-ranking-fixture.json"
    fixture = json.loads(fixture_path.read_text())
    priorities = {1: Priority.P1, 2: Priority.P2, 3: Priority.P3, 4: Priority.P4, 5: Priority.P5}
    tasks = [
        Task(
            id=UUID(row["id"]),
            title=row["label"],
            status=TaskStatus.ON_HEAP,
            created_at=NOW,
            updated_at=NOW,
            priority=priorities[row["priority"]],
            duration=Duration.THIRTY_MINUTES,
            on_heap_since=datetime.fromisoformat(row["on_heap_since"].replace("Z", "+00:00")),
            externally_blocked=row["externally_blocked"],
            due_date=date.fromisoformat(row["due_date"]) if row["due_date"] else None,
        )
        for row in fixture["tasks"]
    ]
    for case in fixture["cases"]:
        ranked = rank_heap_tasks(tasks, today=date.fromisoformat(case["today"]))
        assert [str(task.id) for task in ranked] == case["expected_ids"]


def test_groups_protect_p1_and_promote_due_tasks_only_one_level() -> None:
    """Due urgency promotes P3–P5 once and never alters protected P1/P2 groups."""
    today = date(2026, 10, 5)
    tasks = [
        make_task(1, Priority.P1, today + timedelta(days=1)),
        make_task(2, Priority.P2, today - timedelta(days=100)),
        make_task(3, Priority.P3, today + timedelta(days=1)),
        make_task(4, Priority.P3, today + timedelta(days=2)),
        make_task(5, Priority.P4, today + timedelta(days=1)),
        make_task(6, Priority.P5, today - timedelta(days=1)),
        make_task(7, Priority.P5),
    ]
    assert [task.id.int for task in rank_heap_tasks(tasks, today=today)] == [1, 2, 3, 5, 4, 6, 7]


@pytest.mark.parametrize(
    ("today", "due_date", "urgent"),
    [
        (date(2024, 2, 28), date(2024, 2, 29), True),
        (date(2024, 2, 29), date(2024, 3, 1), True),
        (date(2024, 12, 31), date(2025, 1, 1), True),
        (date(2024, 12, 30), date(2025, 1, 1), False),
        (date.max, date.max, True),
    ],
)
def test_urgency_uses_calendar_day_boundary_without_overflow(
    today: date, due_date: date, urgent: bool
) -> None:
    """Tomorrow comparisons handle leap/month/year transitions and date.max."""
    p3 = make_task(2, Priority.P3, due_date)
    p2 = make_task(1, Priority.P2)
    ranked = rank_heap_tasks([p3, p2], today=today)
    assert (ranked[0] is p3) is urgent


def test_sort_keys_due_null_age_id_and_waiting_do_not_change_rank() -> None:
    """Due date precedes Heap age; age and UUID settle ties regardless of waiting."""
    today = date(2026, 6, 1)
    tasks = [
        make_task(4, Priority.P2, None, 30),
        make_task(3, Priority.P2, date(2026, 6, 9), 1, True),
        make_task(2, Priority.P2, date(2026, 6, 9), 10),
        make_task(1, Priority.P2, date(2026, 6, 9), 10, True),
    ]
    expected = [1, 2, 3, 4]
    assert [task.id.int for task in rank_heap_tasks(tasks, today=today)] == expected
    assert [task.id.int for task in rank_heap_tasks(list(reversed(tasks)), today=today)] == expected


def test_ranking_returns_new_list_without_mutating_input_or_snapshots() -> None:
    """Sorting changes neither the caller's sequence nor task fields."""
    tasks = [make_task(2, Priority.P2), make_task(1, Priority.P1, externally_blocked=True)]
    original_sequence = tasks.copy()
    original_snapshots = [task.__dict__.copy() for task in tasks]
    ranked = rank_heap_tasks(tasks, today=date(2026, 1, 1))
    assert ranked is not tasks
    assert tasks == original_sequence
    assert [task.__dict__ for task in tasks] == original_snapshots
