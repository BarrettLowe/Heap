from abc import ABC, abstractmethod
from datetime import datetime
from uuid import UUID

from heap.logic.task import Task


class TaskStore(ABC):
    """Storage operations for saving, retrieving, and deleting tasks."""

    @abstractmethod
    def save(self, task: Task) -> None:
        """Persist a new task or replace the saved state of an existing task."""

    @abstractmethod
    def save_many(self, tasks: list[Task]) -> None:
        """Save all snapshots in one transaction or roll back every write."""

    @abstractmethod
    def list_unfinished(self) -> list[Task]:
        """Return unfinished snapshots for explicit organization normalization."""

    @abstractmethod
    def get(self, task_id: UUID) -> Task | None:
        """Return a task snapshot, or None if the ID does not exist."""

    @abstractmethod
    def delete(self, task_id: UUID) -> None:
        """Permanently remove a task and its dependency links; missing IDs raise KeyError."""

    @abstractmethod
    def delete_many(self, task_ids: list[UUID]) -> None:
        """Delete tasks and their dependency links together, or roll back on failure.

        Missing IDs raise KeyError. Empty batches do nothing; repeated IDs count once.
        """

    @abstractmethod
    def add_dependency(
        self, task_id: UUID, prerequisite_id: UUID, updated_at: datetime
    ) -> None:
        """Save a link and its dependent task's timestamp in 1 transaction.

        Duplicate links do not change timestamps.
        """

    @abstractmethod
    def remove_dependency(
        self, task_id: UUID, prerequisite_id: UUID, updated_at: datetime
    ) -> None:
        """Remove a link and update its dependent task's timestamp in 1 transaction.

        Absent links do not change timestamps.
        """

    @abstractmethod
    def list_dependencies(self, task_id: UUID) -> list[UUID]:
        """Return prerequisite IDs in ascending ID order."""

    @abstractmethod
    def get_dependency_blocking(self, task_ids: list[UUID]) -> dict[UUID, bool]:
        """Report whether each existing task has an unfinished direct prerequisite.

        Omit missing IDs. Empty batches return {}; repeated IDs count once.
        Ignore the manual external flag and the dependent task's own status.
        """

    @abstractmethod
    def list_inbox(self) -> list[Task]:
        """Return unfinished incomplete snapshots ordered by creation time, then ID."""

    @abstractmethod
    def list_on_heap(self) -> list[Task]:
        """Return qualifying unfinished snapshots ordered by age, then ID."""

    @abstractmethod
    def list_for_project(self, project_id: UUID) -> list[Task]:
        """Return all assigned task snapshots ordered by creation time, then ID."""
