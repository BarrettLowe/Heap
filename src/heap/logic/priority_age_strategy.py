from datetime import datetime, timedelta

from heap.logic.priority import Priority
from heap.logic.ranking_result import RankingScore
from heap.logic.ranking_strategy import RankingStrategy
from heap.logic.task import Task


class PriorityAgeStrategy(RankingStrategy):
    """Rank by priority and capped heap age, optionally allowing priority crossing."""

    def __init__(
        self,
        *,
        allow_age_to_cross_priority: bool = False,
        age_cap_days: int = 60,
    ) -> None:
        """Default to strict priority and the agreed 60-day age cap."""
        if age_cap_days <= 0:
            raise ValueError("The age cap must be positive")
        self.allow_age_to_cross_priority = allow_age_to_cross_priority
        self._age_cap = timedelta(days=age_cap_days)

    def score(self, task: Task, now: datetime) -> RankingScore:
        """Give P1 through P5 5 through 1 points, plus 0 through 1 age point.

        Age grows linearly from heap entry to the cap. Crossing mode sums the
        contributions and lets age win a total-score tie; otherwise priority
        always wins. Eligibility and diversification are not decided here.
        """
        if task.priority is None:
            raise ValueError("Scoring requires priority")
        if task.on_heap_since is None:
            raise ValueError("Scoring requires on_heap_since")
        priority = float(Priority.P5.value + 1 - task.priority.value)
        age = min(max((now - task.on_heap_since) / self._age_cap, 0.0), 1.0)
        leading_score = priority + age if self.allow_age_to_cross_priority else priority
        return RankingScore(
            priority_contribution=priority,
            age_contribution=age,
            sort_key=(leading_score, age),
        )
