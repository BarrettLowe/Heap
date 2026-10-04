from abc import ABC, abstractmethod
from uuid import UUID

from heap.logic.project import Project


class ProjectStore(ABC):
    """Storage operations needed to create and retrieve projects."""

    @abstractmethod
    def save(self, project: Project) -> None:
        """Persist a new project or replace an existing project's saved state."""

    @abstractmethod
    def get(self, project_id: UUID) -> Project | None:
        """Return a project snapshot, or None if the ID does not exist."""

    @abstractmethod
    def list_all(self) -> list[Project]:
        """Return projects ordered by case-insensitive name, then ID."""

    @abstractmethod
    def delete(self, project_id: UUID) -> None:
        """Delete a project and all its assigned tasks atomically; missing IDs raise KeyError."""
