from datetime import UTC, datetime

from heap.logic.ranking_result import RankedTask
from heap.logic.ranking_strategy import RankingStrategy
from heap.logic.task import Task


def current_time() -> datetime:
    """Read current UTC time; tests can replace this time source."""
    return datetime.now(UTC)


class TaskRanker:
    """Score supplied snapshots using a strategy, without filtering or saving them."""

    def __init__(self, strategy: RankingStrategy) -> None:
        """Use the supplied scoring strategy for every ranking."""
        self._strategy = strategy

    def rank(self, tasks: list[Task]) -> list[RankedTask]:
        """Score at 1 UTC instant, sort highest-first, and break ties by ascending ID."""
        if not tasks:
            return []
        now = current_time()
        ranked = [RankedTask(task, self._strategy.score(task, now)) for task in tasks]
        return sorted(
            ranked,
            key=lambda result: (
                -result.score.sort_key[0],
                -result.score.sort_key[1],
                result.task.id,
            ),
        )
