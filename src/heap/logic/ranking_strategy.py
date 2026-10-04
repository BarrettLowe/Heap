from abc import ABC, abstractmethod
from datetime import datetime

from heap.logic.ranking_result import RankingScore
from heap.logic.task import Task


class RankingStrategy(ABC):
    """Score supplied data without storage, time reads, or eligibility decisions."""

    @abstractmethod
    def score(self, task: Task, now: datetime) -> RankingScore:
        """Return contributions and an ordering key using the explicit operation time."""
