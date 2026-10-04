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

    def create(
        self,
        name: str,
        description: str | None = None,
        icon: str | None = None,
        color: str | None = None,
    ) -> Project:
        """Save a new active project and return its in-memory snapshot."""
        now = current_time()
        project = Project(
            id=uuid4(),
            name=name,
            description=description,
            status=ProjectStatus.ACTIVE,
            created_at=now,
            updated_at=now,
            icon=icon,
            color=color,
        )
        self._store.save(project)
        return project

    def get(self, project_id: UUID) -> Project | None:
        """Retrieve a project snapshot, or None if the ID does not exist."""
        return self._store.get(project_id)

    def list_all(self) -> list[Project]:
        """Return all projects in the store's stable display order."""
        return self._store.list_all()

    def update(
        self,
        project_id: UUID,
        name: str,
        description: str | None,
        icon: str | None = None,
        color: str | None = None,
    ) -> Project:
        """Replace editable fields together; missing projects raise KeyError."""
        project = self._store.get(project_id)
        if project is None:
            raise KeyError(project_id)
        if (
            project.name != name
            or project.description != description
            or project.icon != icon
            or project.color != color
        ):
            project.name = name
            project.description = description
            project.icon = icon
            project.color = color
            project.updated_at = current_time()
            self._store.save(project)
        return project

    def delete(self, project_id: UUID) -> None:
        """Delete a project and every task assigned to it."""
        self._store.delete(project_id)

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
