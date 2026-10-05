from __future__ import annotations

from datetime import date, datetime, timedelta
from typing import Sequence

from heap.logic.task import Task


def rank_heap_tasks(tasks: Sequence[Task], *, today: date) -> list[Task]:
    """Return qualifying Heap snapshots in deterministic policy order for today."""
    try:
        tomorrow = today + timedelta(days=1)
    except OverflowError:
        tomorrow = None

    def sort_key(task: Task) -> tuple[int, bool, date, datetime, str]:
        """Build the documented group, due-date, age, and ID ordering key."""
        assert task.priority is not None
        assert task.on_heap_since is not None
        priority = task.priority.value
        urgent = task.due_date is not None and (
            tomorrow is None or task.due_date <= tomorrow
        )
        group = {
            1: 1,
            2: 2,
            3: 2 if urgent else 3,
            4: 3 if urgent else 4,
            5: 4 if urgent else 5,
        }[priority]
        return (
            group,
            task.due_date is None,
            task.due_date or date.max,
            task.on_heap_since,
            str(task.id),
        )

    return sorted(tasks, key=sort_key)
