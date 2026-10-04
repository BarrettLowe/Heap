from dataclasses import dataclass

from heap.logic.task import Task


@dataclass(frozen=True)
class RankingScore:
    """Explain a score and its ordering key; larger key components rank first."""

    priority_contribution: float
    age_contribution: float
    sort_key: tuple[float, float]

    @property
    def total(self) -> float:
        """Sum contributions; the strategy's sort key controls their precedence."""
        return self.priority_contribution + self.age_contribution


@dataclass(frozen=True)
class RankedTask:
    """Pair a supplied task snapshot with its score and explanation contributions."""

    task: Task
    score: RankingScore
