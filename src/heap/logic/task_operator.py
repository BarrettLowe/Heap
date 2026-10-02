from datetime import UTC, datetime
from uuid import UUID, uuid4

from heap.logic.duration import Duration
from heap.logic.priority import Priority
from heap.logic.project_store import ProjectStore
from heap.logic.task import Task, TaskStatus
from heap.logic.task_store import TaskStore


def current_time() -> datetime:
    """Return current UTC time; tests can replace this time source."""
    return datetime.now(UTC)


class TaskOperator:
    """Carry out task operations and save their results."""

    def __init__(
        self, store: TaskStore, project_store: ProjectStore | None = None
    ) -> None:
        """Use task storage and optional project storage for assignment checks."""
        self._store = store
        self._project_store = project_store

    def capture(self, title: str) -> Task:
        """Save a title-only inbox task and return its in-memory snapshot."""
        now = current_time()
        task = Task(
            id=uuid4(),
            title=title,
            status=TaskStatus.INBOX,
            created_at=now,
            updated_at=now,
        )
        self._store.save(task)
        return task

    def list_inbox(self) -> list[Task]:
        """Return inbox snapshots oldest-first, breaking timestamp ties by ID."""
        return self._store.list_inbox()

    def move_to_on_deck(self, task_id: UUID) -> Task:
        """Move an organized inbox task on-deck, preserving time on repeated calls.

        Missing IDs raise KeyError; missing priority or duration raises ValueError.
        Project membership is optional.
        """
        task = self._store.get(task_id)
        if task is None:
            raise KeyError(task_id)
        if task.status is TaskStatus.ON_DECK:
            return task
        if task.priority is None:
            raise ValueError("Moving on-deck requires an assigned priority")
        if task.duration is Duration.UNKNOWN:
            raise ValueError("Moving on-deck requires a known duration")
        now = current_time()
        task.status = TaskStatus.ON_DECK
        task.on_deck_since = now
        task.updated_at = now
        self._store.save(task)
        return task

    def set_title(self, task_id: UUID, title: str) -> Task:
        """Save a title change; missing task IDs raise KeyError."""
        task = self._store.get(task_id)
        if task is None:
            raise KeyError(task_id)
        if task.title != title:
            task.title = title
            task.updated_at = current_time()
            self._store.save(task)
        return task

    def set_project(self, task_id: UUID, project_id: UUID | None) -> Task:
        """Assign an existing project or clear it; missing IDs raise KeyError.

        Assigning a project requires a project store, otherwise ValueError is raised.
        """
        task = self._store.get(task_id)
        if task is None:
            raise KeyError(task_id)
        if project_id is not None:
            if self._project_store is None:
                raise ValueError("Project assignment requires a project store")
            if self._project_store.get(project_id) is None:
                raise KeyError(project_id)
        if task.project_id != project_id:
            task.project_id = project_id
            task.updated_at = current_time()
            self._store.save(task)
        return task

    def set_priority(self, task_id: UUID, priority: Priority | None) -> Task:
        """Save priority; clearing it returns on-deck tasks to the inbox.

        Missing task IDs raise KeyError.
        """
        task = self._store.get(task_id)
        if task is None:
            raise KeyError(task_id)
        if task.priority != priority:
            task.priority = priority
            if priority is None and task.status is TaskStatus.ON_DECK:
                task.status = TaskStatus.INBOX
                task.on_deck_since = None
            task.updated_at = current_time()
            self._store.save(task)
        return task

    def set_duration(self, task_id: UUID, duration: Duration) -> Task:
        """Save duration; unknown returns on-deck tasks to the inbox.

        Missing task IDs raise KeyError.
        """
        task = self._store.get(task_id)
        if task is None:
            raise KeyError(task_id)
        if task.duration != duration:
            task.duration = duration
            if duration is Duration.UNKNOWN and task.status is TaskStatus.ON_DECK:
                task.status = TaskStatus.INBOX
                task.on_deck_since = None
            task.updated_at = current_time()
            self._store.save(task)
        return task
