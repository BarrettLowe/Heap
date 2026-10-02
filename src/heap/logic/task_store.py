from abc import ABC, abstractmethod
from uuid import UUID

from heap.logic.task import Task


class TaskStore(ABC):
    """Storage operations needed to capture and retrieve tasks."""

    @abstractmethod
    def save(self, task: Task) -> None:
        """Persist a new task or replace the saved state of an existing task."""

    @abstractmethod
    def get(self, task_id: UUID) -> Task | None:
        """Return a task snapshot, or None if the ID does not exist."""

    @abstractmethod
    def list_inbox(self) -> list[Task]:
        """Return inbox snapshots ordered by creation time, then ID."""
