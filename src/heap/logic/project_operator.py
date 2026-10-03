from datetime import UTC, datetime
from uuid import UUID, uuid4

from heap.logic.project import Project, ProjectStatus
from heap.logic.project_store import ProjectStore


def current_time() -> datetime:
    """Return current UTC time; tests can replace this time source."""
    return datetime.now(UTC)


class ProjectOperator:
    """Carry out project operations and save their results."""

    def __init__(self, store: ProjectStore) -> None:
        """Use the supplied store for project persistence."""
        self._store = store

    def create(self, name: str, description: str | None = None) -> Project:
        """Save a new active project and return its in-memory snapshot."""
        now = current_time()
        project = Project(
            id=uuid4(),
            name=name,
            description=description,
            status=ProjectStatus.ACTIVE,
            created_at=now,
            updated_at=now,
        )
        self._store.save(project)
        return project

    def get(self, project_id: UUID) -> Project | None:
        """Retrieve a project snapshot, or None if the ID does not exist."""
        return self._store.get(project_id)

    def set_name(self, project_id: UUID, name: str) -> Project:
        """Save a name change; missing project IDs raise KeyError."""
        project = self._store.get(project_id)
        if project is None:
            raise KeyError(project_id)
        if project.name != name:
            project.name = name
            project.updated_at = current_time()
            self._store.save(project)
        return project

    def set_description(self, project_id: UUID, description: str | None) -> Project:
        """Save or clear a description; missing project IDs raise KeyError."""
        project = self._store.get(project_id)
        if project is None:
            raise KeyError(project_id)
        if project.description != description:
            project.description = description
            project.updated_at = current_time()
            self._store.save(project)
        return project
