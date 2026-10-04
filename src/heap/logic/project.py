from dataclasses import dataclass
from datetime import datetime
from enum import StrEnum
from uuid import UUID


class ProjectStatus(StrEnum):
    """The project lifecycle states supported so far."""

    ACTIVE = "active"


@dataclass
class Project:
    """An in-memory project; changes persist only through an explicit save."""

    id: UUID
    name: str
    description: str | None
    status: ProjectStatus
    created_at: datetime
    updated_at: datetime
    completed_at: datetime | None = None
    icon: str | None = None
    color: str | None = None
