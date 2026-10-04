from __future__ import annotations

from dataclasses import replace
from datetime import UTC, datetime, timedelta
from pathlib import Path
from uuid import UUID

import pytest
from pytest import MonkeyPatch

from heap.logic import task_ranker
from heap.logic.duration import Duration
from heap.logic.priority import Priority
from heap.logic.priority_age_strategy import PriorityAgeStrategy
from heap.logic.ranking_result import RankedTask, RankingScore
from heap.logic.ranking_strategy import RankingStrategy
from heap.logic.task import Task, TaskStatus
from heap.logic.task_ranker import TaskRanker
from heap.persistence.sqlite_task_store import SQLiteTaskStore

NOW = datetime(2026, 4, 1, 12, tzinfo=UTC)


def task_snapshot(
    task_id: int,
    priority: Priority | None = Priority.P3,
    age_days: float = 0,
) -> Task:
    """Build a snapshot with heap age independent of creation and update times."""
    return Task(
        id=UUID(int=task_id),
        title=f"Task {task_id}",
        status=TaskStatus.ON_HEAP,
        created_at=NOW - timedelta(days=365),
        updated_at=NOW - timedelta(days=1),
        priority=priority,
        duration=Duration.THIRTY_MINUTES,
        on_heap_since=NOW - timedelta(days=age_days),
    )


@pytest.mark.parametrize(
    ("age_days", "expected"),
    [(-1, 0), (0, 0), (0.5, 1 / 120), (15, 0.25), (30, 0.5), (60, 1), (120, 1)],
)
def test_age_grows_steadily_from_heap_entry_and_stops_at_cap(
    age_days: float,
    expected: float,
) -> None:
    """Age is fractional, nonnegative, and bounded independently of other dates."""
    score = PriorityAgeStrategy().score(task_snapshot(1, age_days=age_days), NOW)
    assert score.age_contribution == pytest.approx(expected)
    assert score.priority_contribution == 3
    assert score.total == pytest.approx(3 + expected)
    assert score.sort_key == (3, score.age_contribution)


@pytest.mark.parametrize("priority", list(Priority))
def test_priority_contributions_are_one_step_apart(priority: Priority) -> None:
    """P1 contributes 5 points and P5 contributes 1 point."""
    score = PriorityAgeStrategy().score(task_snapshot(1, priority), NOW)
    assert score.priority_contribution == 6 - priority.value
    assert score.age_contribution == 0


@pytest.mark.parametrize("age_cap_days", [0, -1])
def test_age_cap_must_be_positive(age_cap_days: int) -> None:
    """Invalid caps fail at construction instead of causing scoring errors."""
    with pytest.raises(ValueError, match="positive"):
        PriorityAgeStrategy(age_cap_days=age_cap_days)


def test_age_cap_is_configurable() -> None:
    """Changing the cap changes growth speed, not the maximum contribution."""
    strategy = PriorityAgeStrategy(age_cap_days=30)
    assert strategy.score(task_snapshot(1, age_days=15), NOW).age_contribution == 0.5
    assert strategy.score(task_snapshot(1, age_days=30), NOW).age_contribution == 1
    assert strategy.score(task_snapshot(1, age_days=90), NOW).age_contribution == 1


@pytest.mark.parametrize("missing", ["priority", "on_heap_since"])
def test_scoring_requires_its_input_data_without_silently_filtering(
    missing: str,
) -> None:
    """Scoring errors report missing data rather than making eligibility decisions."""
    task = replace(task_snapshot(1), **{missing: None})
    with pytest.raises(ValueError, match=missing):
        PriorityAgeStrategy().score(task, NOW)


@pytest.mark.parametrize("allow_crossing", [False, True])
@pytest.mark.parametrize("higher", [Priority.P1, Priority.P2, Priority.P3, Priority.P4])
def test_age_only_crosses_one_priority_step_when_enabled(
    monkeypatch: MonkeyPatch,
    allow_crossing: bool,
    higher: Priority,
) -> None:
    """The age tie-break only overrides the adjacent priority when opted in."""
    monkeypatch.setattr(task_ranker, "current_time", lambda: NOW)
    fresh = task_snapshot(1, higher)
    capped = task_snapshot(2, Priority(higher.value + 1), age_days=60)
    strategy = PriorityAgeStrategy(allow_age_to_cross_priority=allow_crossing)
    ranked = TaskRanker(strategy).rank([fresh, capped])
    assert [result.task.id for result in ranked] == (
        [capped.id, fresh.id] if allow_crossing else [fresh.id, capped.id]
    )
    assert ranked[0].score.total == ranked[1].score.total


@pytest.mark.parametrize("higher", [Priority.P1, Priority.P2, Priority.P3])
def test_capped_age_never_crosses_two_priority_steps(
    monkeypatch: MonkeyPatch,
    higher: Priority,
) -> None:
    """Even a very old task cannot gain more than 1 priority step."""
    monkeypatch.setattr(task_ranker, "current_time", lambda: NOW)
    fresh = task_snapshot(2, higher)
    old = task_snapshot(1, Priority(higher.value + 2), age_days=600)
    ranker = TaskRanker(PriorityAgeStrategy(allow_age_to_cross_priority=True))
    assert [result.task.id for result in ranker.rank([old, fresh])] == [
        fresh.id,
        old.id,
    ]


@pytest.mark.parametrize("allow_crossing", [False, True])
def test_age_reorders_same_priority_in_both_modes(
    monkeypatch: MonkeyPatch,
    allow_crossing: bool,
) -> None:
    """Older tasks in the same priority receive higher positions below the cap."""
    monkeypatch.setattr(task_ranker, "current_time", lambda: NOW)
    fresh = task_snapshot(1)
    middle = task_snapshot(3, age_days=15)
    old = task_snapshot(2, age_days=30)
    ranker = TaskRanker(PriorityAgeStrategy(allow_age_to_cross_priority=allow_crossing))
    ranked = ranker.rank([fresh, old, middle])
    assert [result.task.id for result in ranked] == [old.id, middle.id, fresh.id]
    assert [result.score.age_contribution for result in ranked] == [0.5, 0.25, 0]


@pytest.mark.parametrize("allow_crossing", [False, True])
def test_capped_ties_use_id_not_extra_age_or_input_order(
    monkeypatch: MonkeyPatch,
    allow_crossing: bool,
) -> None:
    """Equal scores stay deterministic without rewarding age past the cap."""
    monkeypatch.setattr(task_ranker, "current_time", lambda: NOW)
    capped = task_snapshot(1, age_days=60)
    older = task_snapshot(2, age_days=600)
    ranker = TaskRanker(PriorityAgeStrategy(allow_age_to_cross_priority=allow_crossing))
    expected = [capped.id, older.id]
    assert [result.task.id for result in ranker.rank([older, capped])] == expected
    assert [result.task.id for result in ranker.rank([capped, older])] == expected


@pytest.mark.parametrize("allow_crossing", [False, True])
def test_uncapped_age_cannot_overtake_higher_priority(
    monkeypatch: MonkeyPatch,
    allow_crossing: bool,
) -> None:
    """A task just below the cap still loses to a fresh adjacent higher priority."""
    monkeypatch.setattr(task_ranker, "current_time", lambda: NOW)
    fresh = task_snapshot(2, Priority.P2)
    almost_capped = task_snapshot(1, Priority.P3, age_days=59.999)
    ranker = TaskRanker(PriorityAgeStrategy(allow_age_to_cross_priority=allow_crossing))
    assert [result.task.id for result in ranker.rank([almost_capped, fresh])] == [
        fresh.id,
        almost_capped.id,
    ]


def test_unrelated_fields_do_not_influence_score_or_filter_tasks(
    monkeypatch: MonkeyPatch,
) -> None:
    """Duration, project, waiting, and lifecycle filtering remain outside scoring."""
    monkeypatch.setattr(task_ranker, "current_time", lambda: NOW)
    base = task_snapshot(1, age_days=30)
    variants = [
        base,
        replace(base, id=UUID(int=2), duration=Duration.UNKNOWN),
        replace(base, id=UUID(int=3), project_id=UUID(int=99)),
        replace(base, id=UUID(int=4), externally_blocked=True),
        replace(base, id=UUID(int=5), status=TaskStatus.COMPLETED),
        replace(base, id=UUID(int=6), created_at=NOW, updated_at=NOW),
    ]
    ranked = TaskRanker(PriorityAgeStrategy()).rank(list(reversed(variants)))
    assert [result.task for result in ranked] == variants
    assert all(result.score == ranked[0].score for result in ranked)


class IdStrategy(RankingStrategy):
    """Test strategy that favors larger IDs and records every scoring time."""

    def __init__(self) -> None:
        """Start with no recorded calls."""
        self.times: list[datetime] = []

    def score(self, task: Task, now: datetime) -> RankingScore:
        """Give each task an ID-based key unrelated to its priority."""
        self.times.append(now)
        value = float(task.id.int)
        return RankingScore(
            priority_contribution=value,
            age_contribution=0,
            sort_key=(value, 0),
        )


def test_ranker_uses_injected_strategy_and_reads_one_shared_utc_instant(
    monkeypatch: MonkeyPatch,
) -> None:
    """Every score sees the same operation time and ordering follows the strategy."""
    reads = 0

    def read_time() -> datetime:
        """Count time reads and return a different instant on every call."""
        nonlocal reads
        reads += 1
        return NOW + timedelta(seconds=reads)

    monkeypatch.setattr(task_ranker, "current_time", read_time)
    strategy = IdStrategy()
    tasks = [task_snapshot(1, Priority.P1), task_snapshot(2, Priority.P5)]
    ranked = TaskRanker(strategy).rank(tasks)
    assert reads == 1
    assert strategy.times == [NOW + timedelta(seconds=1)] * 2
    assert [result.task.id for result in ranked] == [tasks[1].id, tasks[0].id]
    assert ranked[0] == RankedTask(
        tasks[1], strategy.score(tasks[1], strategy.times[0])
    )


def test_ranker_can_read_utc_time_without_a_caller_supplied_timestamp() -> None:
    """The normal entry point supplies UTC time to the strategy itself."""
    strategy = IdStrategy()
    TaskRanker(strategy).rank([task_snapshot(1)])
    assert len(strategy.times) == 1
    assert strategy.times[0].tzinfo is UTC


def test_cross_priority_flag_can_be_changed_on_the_strategy(
    monkeypatch: MonkeyPatch,
) -> None:
    """Changing the flag switches precedence without replacing the ranker."""
    monkeypatch.setattr(task_ranker, "current_time", lambda: NOW)
    fresh = task_snapshot(1, Priority.P2)
    old = task_snapshot(2, Priority.P3, age_days=60)
    strategy = PriorityAgeStrategy()
    ranker = TaskRanker(strategy)
    assert [result.task.id for result in ranker.rank([old, fresh])] == [
        fresh.id,
        old.id,
    ]
    strategy.allow_age_to_cross_priority = True
    assert [result.task.id for result in ranker.rank([old, fresh])] == [
        old.id,
        fresh.id,
    ]


def test_empty_ranking_reads_no_time(monkeypatch: MonkeyPatch) -> None:
    """An empty input performs no scoring or time read."""

    def unexpected_time() -> datetime:
        """Fail if an empty ranking requests time."""
        pytest.fail("Empty ranking read time")

    monkeypatch.setattr(task_ranker, "current_time", unexpected_time)
    strategy = IdStrategy()
    assert TaskRanker(strategy).rank([]) == []
    assert strategy.times == []


def test_strategy_interface_requires_a_scoring_implementation() -> None:
    """The scoring boundary is an abstract class, not an implicit convention."""
    with pytest.raises(TypeError, match="abstract"):
        RankingStrategy()


def test_ranking_is_read_only_and_repeatable_with_persisted_snapshots(
    tmp_path: Path,
    monkeypatch: MonkeyPatch,
) -> None:
    """Ranking neither mutates input snapshots nor saves their score to storage."""
    monkeypatch.setattr(task_ranker, "current_time", lambda: NOW)
    database = tmp_path / "heap.sqlite"
    original = [task_snapshot(2, age_days=30), task_snapshot(1, Priority.P1)]
    before = [replace(task) for task in original]
    with SQLiteTaskStore(database) as store:
        store.save_many(original)
        ranker = TaskRanker(PriorityAgeStrategy())
        ranked = ranker.rank(original)
        assert original == before
        assert ranker.rank(list(reversed(original))) == ranked
    with SQLiteTaskStore(database) as store:
        assert [store.get(task.id) for task in original] == before
        assert [result.task.id for result in ranked] == [original[1].id, original[0].id]
