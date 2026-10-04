from datetime import UTC, datetime
from pathlib import Path
from uuid import uuid4

import pytest
from pytest import MonkeyPatch

from heap.logic import project_operator
from heap.logic.project import ProjectStatus
from heap.logic.project_operator import ProjectOperator
from heap.persistence.sqlite_project_store import SQLiteProjectStore


# Cases: creation survives reopening, with and without a description;
# unknown ID returns None; snapshot changes persist only after an explicit save.


@pytest.mark.parametrize("description", [None, "Replace the damaged north fence"])
def test_created_project_survives_database_reopen(
    tmp_path: Path, monkeypatch: MonkeyPatch, description: str | None
) -> None:
    """Creating a project saves its state and fixed UTC timestamps."""
    now = datetime(2026, 1, 2, 12, 0, tzinfo=UTC)
    monkeypatch.setattr(project_operator, "current_time", lambda: now)
    database = tmp_path / "heap.sqlite"

    with SQLiteProjectStore(database) as store:
        project = ProjectOperator(store).create("Repair the fence", description)

    with SQLiteProjectStore(database) as store:
        saved = ProjectOperator(store).get(project.id)

    assert saved == project
    assert saved is not project
    assert project.name == "Repair the fence"
    assert project.description == description
    assert project.status is ProjectStatus.ACTIVE
    assert project.created_at == now
    assert project.updated_at == now
    assert project.completed_at is None


def test_unknown_project_id_returns_none(tmp_path: Path) -> None:
    """Retrieving an absent project returns None."""
    with SQLiteProjectStore(tmp_path / "heap.sqlite") as store:
        assert ProjectOperator(store).get(uuid4()) is None


def test_project_changes_persist_only_after_explicit_save(tmp_path: Path) -> None:
    """Project snapshots do not automatically write changes to storage."""
    database = tmp_path / "heap.sqlite"
    with SQLiteProjectStore(database) as store:
        projects = ProjectOperator(store)
        project = projects.create("Repair the fence")
        project.name = "Replace the north fence"
        project.icon = "home-outline"
        project.color = "#336699"
        saved = projects.get(project.id)
        assert saved is not None
        assert saved.name == "Repair the fence"
        assert saved.icon is None
        assert saved.color is None
        store.save(project)

    with SQLiteProjectStore(database) as store:
        saved = ProjectOperator(store).get(project.id)
        assert saved == project
        assert saved is not None
        assert saved.icon == "home-outline"
        assert saved.color == "#336699"
