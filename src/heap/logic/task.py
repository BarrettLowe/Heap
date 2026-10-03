from dataclasses import dataclass
from datetime import datetime
from enum import StrEnum
from uuid import UUID

from heap.logic.duration import Duration
from heap.logic.priority import Priority


class TaskStatus(StrEnum):
    """The lifecycle states supported so far."""

    INBOX = "inbox"
    ON_DECK = "on_deck"
    COMPLETED = "completed"


@dataclass
class Task:
    """An in-memory task; changes are persisted only by an explicit save."""

    id: UUID
    title: str
    status: TaskStatus
    created_at: datetime
    updated_at: datetime
    priority: Priority | None = None
    duration: Duration = Duration.UNKNOWN
    project_id: UUID | None = None
    on_deck_since: datetime | None = None
    completed_at: datetime | None = None
    externally_blocked: bool = False
