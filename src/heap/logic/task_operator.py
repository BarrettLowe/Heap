from dataclasses import replace
from datetime import UTC, date, datetime, timedelta
from uuid import UUID, uuid4

from heap.logic.duration import Duration
from heap.logic.priority import Priority
from heap.logic.project_store import ProjectStore
from heap.logic.task import Task, TaskStatus
from heap.logic.task_ranking import rank_heap_tasks
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

    def get(self, task_id: UUID) -> Task:
        """Return a fresh task snapshot; missing IDs raise KeyError."""
        task = self._store.get(task_id)
        if task is None:
            raise KeyError(task_id)
        return task

    def list_inbox(self) -> list[Task]:
        """Return inbox snapshots oldest-first, breaking timestamp ties by ID."""
        return self._store.list_inbox()

    def list_on_heap(self, *, today: date) -> list[Task]:
        """Return qualifying unfinished snapshots in the agreed Heap order."""
        return rank_heap_tasks(self._store.list_on_heap(), today=today)

    def list_for_project(self, project_id: UUID) -> list[Task]:
        """Return all assigned task snapshots; unknown projects raise KeyError."""
        if self._project_store is None or self._project_store.get(project_id) is None:
            raise KeyError(project_id)
        return self._store.list_for_project(project_id)

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

    def complete_on_heap(self, task_id: UUID) -> Task:
        """Complete a task currently on Heap, retaining its age for undo.

        Missing IDs raise KeyError; tasks without Heap placement raise ValueError.
        """
        task = self.get(task_id)
        if task.status is TaskStatus.COMPLETED:
            return task
        if task.status is not TaskStatus.ON_HEAP or task.on_heap_since is None:
            raise ValueError("Only a task on Heap can be completed")
        now = current_time()
        task.status = TaskStatus.COMPLETED
        task.completed_at = now
        task.updated_at = max(now, task.updated_at + timedelta(microseconds=1))
        self._store.save(task)
        return task

    def undo_completion(self, task_id: UUID) -> Task:
        """Restore a completed task to its retained qualifying Heap placement.

        Missing IDs raise KeyError; tasks without saved Heap history raise ValueError.
        """
        task = self.get(task_id)
        if task.status is not TaskStatus.COMPLETED:
            return task
        if (
            task.on_heap_since is None
            or task.priority is None
            or task.duration is Duration.UNKNOWN
        ):
            raise ValueError("Completed task has no qualifying Heap history")
        now = max(current_time(), task.updated_at + timedelta(microseconds=1))
        task.status = TaskStatus.ON_HEAP
        task.completed_at = None
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

    def organize_task(
        self,
        task_id: UUID,
        *,
        title: str,
        priority: Priority | None,
        duration: Duration,
        externally_blocked: bool,
        project_id: UUID | None = None,
        due_date: date | None,
    ) -> Task:
        """Replace editor fields together and derive placement from requirements.

        Missing IDs raise KeyError; completed tasks raise ValueError.
        Unchanged final snapshots do not read time or save.
        """
        task = self.get(task_id)
        if task.status is TaskStatus.COMPLETED:
            raise ValueError("A completed task cannot be organized")
        if project_id is not None and project_id != task.project_id:
            if self._project_store is None:
                raise ValueError("Project assignment requires a project store")
            if self._project_store.get(project_id) is None:
                raise KeyError(project_id)
        return self._save_edit(
            task,
            replace(
                task,
                title=title,
                priority=priority,
                duration=duration,
                externally_blocked=externally_blocked,
                project_id=project_id,
                due_date=due_date,
            ),
        )

    @staticmethod
    def _qualifies(task: Task) -> bool:
        """Check organization requirements independently of blocking flags."""
        return (
            task.status is not TaskStatus.COMPLETED
            and task.priority is not None
            and task.duration is not Duration.UNKNOWN
        )

    @staticmethod
    def _derive_organization(task: Task) -> None:
        """Derive unfinished placement, leaving entry time for the saving operation."""
        if task.status is TaskStatus.COMPLETED:
            return
        if TaskOperator._qualifies(task):
            if task.status is not TaskStatus.ON_HEAP:
                task.on_heap_since = None
            task.status = TaskStatus.ON_HEAP
        else:
            task.status = TaskStatus.INBOX
            task.on_heap_since = None

    def _save_edit(self, original: Task, edited: Task) -> Task:
        """Save a changed final snapshot once with one operation time read."""
        self._derive_organization(edited)
        needs_entry_time = (
            edited.status is TaskStatus.ON_HEAP and edited.on_heap_since is None
        )
        if edited == original and not needs_entry_time:
            return original
        now = current_time()
        if needs_entry_time:
            edited.on_heap_since = now
        edited.updated_at = max(now, original.updated_at + timedelta(microseconds=1))
        self._store.save(edited)
        return edited

    def normalize_organization(self) -> int:
        """Atomically promote qualifying legacy Inbox snapshots using actual time.

        Already-normalized and unrelated snapshots are untouched. Empty work
        reads no time and saves nothing; failed persistence reports no count.
        """
        tasks = [
            task
            for task in self._store.list_unfinished()
            if task.status is TaskStatus.INBOX and self._qualifies(task)
        ]
        if not tasks:
            return 0
        now = current_time()
        for task in tasks:
            task.status = TaskStatus.ON_HEAP
            task.on_heap_since = now
            task.updated_at = now
        self._store.save_many(tasks)
        return len(tasks)

    def move_to_heap(self, task_id: UUID) -> Task:
        """Compatibility call to normalize a qualifying task's organization.

        Missing IDs raise KeyError. Completed tasks and tasks missing priority
        or duration raise ValueError. Project membership is optional.
        """
        task = self._store.get(task_id)
        if task is None:
            raise KeyError(task_id)
        if task.status is TaskStatus.COMPLETED:
            raise ValueError("A completed task cannot move onto the heap")
        if task.priority is None:
            raise ValueError("Moving onto the heap requires an assigned priority")
        if task.duration is Duration.UNKNOWN:
            raise ValueError("Moving onto the heap requires a known duration")
        return self._save_edit(task, replace(task))

    def set_externally_blocked(self, task_id: UUID, externally_blocked: bool) -> Task:
        """Save the manual external-blocking flag; missing task IDs raise KeyError."""
        task = self._store.get(task_id)
        if task is None:
            raise KeyError(task_id)
        return self._save_edit(
            task, replace(task, externally_blocked=externally_blocked)
        )

    def set_title(self, task_id: UUID, title: str) -> Task:
        """Save a title change; missing task IDs raise KeyError."""
        task = self._store.get(task_id)
        if task is None:
            raise KeyError(task_id)
        return self._save_edit(task, replace(task, title=title))

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
        return self._save_edit(task, replace(task, project_id=project_id))

    def set_priority(self, task_id: UUID, priority: Priority | None) -> Task:
        """Save priority and automatically derive unfinished task placement.

        Missing task IDs raise KeyError.
        """
        task = self._store.get(task_id)
        if task is None:
            raise KeyError(task_id)
        return self._save_edit(task, replace(task, priority=priority))

    def set_duration(self, task_id: UUID, duration: Duration) -> Task:
        """Save duration and automatically derive unfinished task placement.

        Missing task IDs raise KeyError.
        """
        task = self._store.get(task_id)
        if task is None:
            raise KeyError(task_id)
        return self._save_edit(task, replace(task, duration=duration))
