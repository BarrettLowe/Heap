from datetime import UTC, datetime
from pathlib import Path
from uuid import uuid4

import pytest
from pytest import MonkeyPatch

from heap.logic import task_operator
from heap.logic.duration import Duration
from heap.logic.priority import Priority
from heap.logic.project_operator import ProjectOperator
from heap.logic.task import Task, TaskStatus
from heap.logic.task_operator import TaskOperator
from heap.persistence.sqlite_project_store import SQLiteProjectStore
from heap.persistence.sqlite_task_store import SQLiteTaskStore


# Cases: standalone and project-associated tasks move on-deck; missing priority
# or duration rejects the move; repeated moves are no-ops; edits preserve age;
# unknown task IDs fail without creating a task.

CREATED: datetime = datetime(2026, 1, 2, 12, 0, tzinfo=UTC)
ON_DECK: datetime = datetime(2026, 1, 3, 12, 0, tzinfo=UTC)
LATER: datetime = datetime(2026, 1, 4, 12, 0, tzinfo=UTC)


@pytest.mark.parametrize("with_project", [False, True])
def test_move_to_on_deck_survives_reopening(
    tmp_path: Path, monkeypatch: MonkeyPatch, with_project: bool
) -> None:
    """Organized tasks move on-deck with or without project membership."""
    database = tmp_path / "heap.sqlite"
    monkeypatch.setattr(task_operator, "current_time", lambda: CREATED)
    with SQLiteProjectStore(database) as project_store:
        with SQLiteTaskStore(database) as store:
            tasks = TaskOperator(store, project_store)
            captured = tasks.capture("Repair the fence")
            assert captured.on_deck_since is None
            tasks.set_priority(captured.id, Priority.P2)
            tasks.set_duration(captured.id, Duration.THIRTY_MINUTES)
            project_id = None
            if with_project:
                project = ProjectOperator(project_store).create("Fence repair")
                project_id = project.id
                tasks.set_project(captured.id, project_id)
            monkeypatch.setattr(task_operator, "current_time", lambda: ON_DECK)
            moved = tasks.move_to_on_deck(captured.id)

    with SQLiteTaskStore(database) as store:
        assert store.get(captured.id) == moved
        assert TaskOperator(store).list_inbox() == []
    assert moved.status is TaskStatus.ON_DECK
    assert moved.on_deck_since == ON_DECK
    assert moved.updated_at == ON_DECK
    assert moved.created_at == CREATED
    assert moved.title == captured.title
    assert moved.priority is Priority.P2
    assert moved.duration is Duration.THIRTY_MINUTES
    assert moved.project_id == project_id


@pytest.mark.parametrize(
    ("priority", "duration"),
    [
        (None, Duration.THIRTY_MINUTES),
        (Priority.P2, Duration.UNKNOWN),
        (None, Duration.UNKNOWN),
    ],
)
def test_missing_priority_or_duration_keeps_task_in_inbox(
    tmp_path: Path, monkeypatch: MonkeyPatch,
    priority: Priority | None, duration: Duration,
) -> None:
    """A rejected move leaves the saved status and timestamps unchanged."""
    monkeypatch.setattr(task_operator, "current_time", lambda: CREATED)
    database = tmp_path / "heap.sqlite"
    with SQLiteTaskStore(database) as store:
        tasks = TaskOperator(store)
        task = tasks.capture("Repair the fence")
        tasks.set_priority(task.id, priority)
        before = tasks.set_duration(task.id, duration)
        monkeypatch.setattr(task_operator, "current_time", lambda: ON_DECK)
        with pytest.raises(ValueError):
            tasks.move_to_on_deck(task.id)

    with SQLiteTaskStore(database) as store:
        assert store.get(task.id) == before
        assert TaskOperator(store).list_inbox() == [before]
    assert before.status is TaskStatus.INBOX
    assert before.on_deck_since is None


def test_repeated_move_does_not_save_or_reset_timestamps(
    tmp_path: Path, monkeypatch: MonkeyPatch
) -> None:
    """Moving an already-on-deck task preserves its original age."""
    def unexpected_save(task: Task) -> None:
        """Fail if a repeated move tries to save."""
        pytest.fail("An already-on-deck task should not be saved again")

    with SQLiteTaskStore(tmp_path / "heap.sqlite") as store:
        tasks = TaskOperator(store)
        task = tasks.capture("Repair the fence")
        tasks.set_priority(task.id, Priority.P2)
        tasks.set_duration(task.id, Duration.THIRTY_MINUTES)
        monkeypatch.setattr(task_operator, "current_time", lambda: ON_DECK)
        moved = tasks.move_to_on_deck(task.id)
        monkeypatch.setattr(task_operator, "current_time", lambda: LATER)
        monkeypatch.setattr(store, "save", unexpected_save)
        assert tasks.move_to_on_deck(task.id) == moved


def test_edits_do_not_reset_on_deck_since(tmp_path: Path, monkeypatch: MonkeyPatch) -> None:
    """Ordinary edits change updated_at, not the timestamp used for task age."""
    database = tmp_path / "heap.sqlite"
    with SQLiteTaskStore(database) as store:
        tasks = TaskOperator(store)
        task = tasks.capture("Repair the fence")
        tasks.set_priority(task.id, Priority.P2)
        tasks.set_duration(task.id, Duration.THIRTY_MINUTES)
        monkeypatch.setattr(task_operator, "current_time", lambda: ON_DECK)
        tasks.move_to_on_deck(task.id)
        monkeypatch.setattr(task_operator, "current_time", lambda: LATER)
        tasks.set_title(task.id, "Replace the north fence boards")
        tasks.set_priority(task.id, Priority.P1)
        edited = tasks.set_duration(task.id, Duration.ONE_HOUR)

    with SQLiteTaskStore(database) as store:
        assert store.get(task.id) == edited
    assert edited.status is TaskStatus.ON_DECK
    assert edited.on_deck_since == ON_DECK
    assert edited.updated_at == LATER


def test_moving_missing_task_raises_key_error(tmp_path: Path) -> None:
    """A missing task cannot be moved on-deck."""
    with SQLiteTaskStore(tmp_path / "heap.sqlite") as store:
        tasks = TaskOperator(store)
        with pytest.raises(KeyError):
            tasks.move_to_on_deck(uuid4())
        assert tasks.list_inbox() == []


@pytest.mark.parametrize("cleared_field", ["priority", "duration"])
def test_clearing_required_field_returns_on_deck_task_to_inbox(
    tmp_path: Path, monkeypatch: MonkeyPatch, cleared_field: str
) -> None:
    """Removing priority or duration saves an inbox task with no on-deck age."""
    database = tmp_path / "heap.sqlite"
    monkeypatch.setattr(task_operator, "current_time", lambda: CREATED)
    with SQLiteTaskStore(database) as store:
        tasks = TaskOperator(store)
        task = tasks.capture("Repair the fence")
        tasks.set_priority(task.id, Priority.P2)
        tasks.set_duration(task.id, Duration.THIRTY_MINUTES)
        monkeypatch.setattr(task_operator, "current_time", lambda: ON_DECK)
        tasks.move_to_on_deck(task.id)
        monkeypatch.setattr(task_operator, "current_time", lambda: LATER)
        if cleared_field == "priority":
            edited = tasks.set_priority(task.id, None)
            assert edited.priority is None
            assert edited.duration is Duration.THIRTY_MINUTES
        else:
            edited = tasks.set_duration(task.id, Duration.UNKNOWN)
            assert edited.duration is Duration.UNKNOWN
            assert edited.priority is Priority.P2

    with SQLiteTaskStore(database) as store:
        assert store.get(task.id) == edited
        assert TaskOperator(store).list_inbox() == [edited]
    assert edited.status is TaskStatus.INBOX
    assert edited.on_deck_since is None
    assert edited.updated_at == LATER
    assert edited.created_at == CREATED
    assert edited.title == task.title


@pytest.mark.parametrize("cleared_field", ["priority", "duration"])
def test_restoring_required_field_needs_explicit_move_with_new_on_deck_time(
    tmp_path: Path, monkeypatch: MonkeyPatch, cleared_field: str
) -> None:
    """Restoring organization does not automatically move a task on-deck."""
    database = tmp_path / "heap.sqlite"
    with SQLiteTaskStore(database) as store:
        tasks = TaskOperator(store)
        task = tasks.capture("Repair the fence")
        tasks.set_priority(task.id, Priority.P2)
        tasks.set_duration(task.id, Duration.THIRTY_MINUTES)
        monkeypatch.setattr(task_operator, "current_time", lambda: ON_DECK)
        tasks.move_to_on_deck(task.id)
        monkeypatch.setattr(task_operator, "current_time", lambda: LATER)
        if cleared_field == "priority":
            tasks.set_priority(task.id, None)
            restored = tasks.set_priority(task.id, Priority.P2)
        else:
            tasks.set_duration(task.id, Duration.UNKNOWN)
            restored = tasks.set_duration(task.id, Duration.THIRTY_MINUTES)
        assert restored.status is TaskStatus.INBOX
        assert restored.on_deck_since is None
        assert tasks.list_inbox() == [restored]
        moved = tasks.move_to_on_deck(task.id)
        assert moved.status is TaskStatus.ON_DECK
        assert moved.on_deck_since == LATER

    with SQLiteTaskStore(database) as store:
        assert store.get(task.id) == moved
        assert TaskOperator(store).list_inbox() == []
