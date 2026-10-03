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

    def complete(self, task_id: UUID) -> Task:
        """Retain a task as completed; repeated completion leaves it unchanged.

        Missing task IDs raise KeyError.
        """
        task = self._store.get(task_id)
        if task is None:
            raise KeyError(task_id)
        if task.status is TaskStatus.COMPLETED:
            return task
        now = current_time()
        task.status = TaskStatus.COMPLETED
        task.completed_at = now
        task.updated_at = now
        self._store.save(task)
        return task

    def delete(self, task_id: UUID) -> None:
        """Permanently delete a task and its dependency links; missing IDs raise KeyError."""
        self._store.delete(task_id)

    def delete_many(self, task_ids: list[UUID]) -> None:
        """Delete a batch and its dependency links, rolling back if any deletion fails.

        Missing IDs raise KeyError. Empty batches do nothing; repeated IDs count once.
        """
        self._store.delete_many(task_ids)

    def add_dependency(self, task_id: UUID, prerequisite_id: UUID) -> None:
        """Save a prerequisite link; duplicate links leave timestamps unchanged.

        Missing IDs raise KeyError; self-dependencies and cycles raise ValueError.
        Cycle validation assumes dependency edits do not run concurrently.
        """
        if self._store.get(task_id) is None:
            raise KeyError(task_id)
        if self._store.get(prerequisite_id) is None:
            raise KeyError(prerequisite_id)
        if task_id == prerequisite_id:
            raise ValueError("A task cannot depend on itself")
        if prerequisite_id in self._store.list_dependencies(task_id):
            return
        pending = [prerequisite_id]
        visited: set[UUID] = set()
        while pending:
            current_id = pending.pop()
            if current_id == task_id:
                raise ValueError("A dependency cannot create a cycle")
            if current_id not in visited:
                visited.add(current_id)
                pending.extend(self._store.list_dependencies(current_id))
        self._store.add_dependency(task_id, prerequisite_id, current_time())

    def remove_dependency(self, task_id: UUID, prerequisite_id: UUID) -> None:
        """Remove a prerequisite link; absent links leave timestamps unchanged.

        Missing task or prerequisite IDs raise KeyError.
        """
        if self._store.get(task_id) is None:
            raise KeyError(task_id)
        if self._store.get(prerequisite_id) is None:
            raise KeyError(prerequisite_id)
        if prerequisite_id in self._store.list_dependencies(task_id):
            self._store.remove_dependency(task_id, prerequisite_id, current_time())

    def list_dependencies(self, task_id: UUID) -> list[UUID]:
        """Return prerequisite IDs in ascending ID order; missing IDs raise KeyError."""
        if self._store.get(task_id) is None:
            raise KeyError(task_id)
        return self._store.list_dependencies(task_id)

    def is_dependency_blocked(self, task_id: UUID) -> bool:
        """Check for an unfinished direct prerequisite; missing IDs raise KeyError."""
        return self.get_dependency_blocking([task_id])[task_id]

    def get_dependency_blocking(self, task_ids: list[UUID]) -> dict[UUID, bool]:
        """Check direct prerequisites in bulk, without deciding task eligibility.

        Missing IDs raise KeyError in input order. Empty batches return {};
        repeated IDs count once. The manual external flag is not considered.
        """
        blocking = self._store.get_dependency_blocking(task_ids)
        for task_id in task_ids:
            if task_id not in blocking:
                raise KeyError(task_id)
        return blocking

    def move_to_on_deck(self, task_id: UUID) -> Task:
        """Move an organized inbox task on-deck, preserving time on repeated calls.

        Missing IDs raise KeyError. Completed tasks and tasks missing priority
        or duration raise ValueError. Project membership is optional.
        """
        task = self._store.get(task_id)
        if task is None:
            raise KeyError(task_id)
        if task.status is TaskStatus.ON_DECK:
            return task
        if task.status is TaskStatus.COMPLETED:
            raise ValueError("A completed task cannot move on-deck")
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

    def set_externally_blocked(self, task_id: UUID, externally_blocked: bool) -> Task:
        """Save the manual external-blocking flag; missing task IDs raise KeyError."""
        task = self._store.get(task_id)
        if task is None:
            raise KeyError(task_id)
        if task.externally_blocked != externally_blocked:
            task.externally_blocked = externally_blocked
            task.updated_at = current_time()
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
