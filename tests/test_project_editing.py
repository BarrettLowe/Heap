from dataclasses import replace
from datetime import UTC, datetime
from pathlib import Path
from uuid import uuid4

import pytest
from pytest import MonkeyPatch

from heap.logic import project_operator
from heap.logic.project import Project
from heap.logic.project_operator import ProjectOperator
from heap.persistence.sqlite_project_store import SQLiteProjectStore


CREATED: datetime = datetime(2026, 1, 2, 12, 0, tzinfo=UTC)
EDITED: datetime = datetime(2026, 1, 3, 12, 0, tzinfo=UTC)


def test_name_edit_persists_and_preserves_other_fields(
    tmp_path: Path, monkeypatch: MonkeyPatch
) -> None:
    """A name edit saves its timestamp and leaves other project fields alone."""
    database = tmp_path / "heap.sqlite"
    monkeypatch.setattr(project_operator, "current_time", lambda: CREATED)
    with SQLiteProjectStore(database) as store:
        projects = ProjectOperator(store)
        original = projects.create("Repair the fence", "Replace damaged boards")
        monkeypatch.setattr(project_operator, "current_time", lambda: EDITED)
        edited = projects.set_name(original.id, "Replace the north fence")

    assert edited == replace(
        original, name="Replace the north fence", updated_at=EDITED
    )
    with SQLiteProjectStore(database) as store:
        assert ProjectOperator(store).get(original.id) == edited


@pytest.mark.parametrize(
    ("original_description", "description"),
    [
        (None, "Replace damaged boards"),
        ("Replace damaged boards", "Replace the entire north fence"),
        ("Replace damaged boards", None),
    ],
)
def test_description_edits_persist_and_preserve_other_fields(
    tmp_path: Path,
    monkeypatch: MonkeyPatch,
    original_description: str | None,
    description: str | None,
) -> None:
    """Adding, changing, and clearing a description saves only the intended edit."""
    database = tmp_path / "heap.sqlite"
    monkeypatch.setattr(project_operator, "current_time", lambda: CREATED)
    with SQLiteProjectStore(database) as store:
        projects = ProjectOperator(store)
        original = projects.create("Repair the fence", original_description)
        monkeypatch.setattr(project_operator, "current_time", lambda: EDITED)
        edited = projects.set_description(original.id, description)

    assert edited == replace(original, description=description, updated_at=EDITED)
    with SQLiteProjectStore(database) as store:
        assert ProjectOperator(store).get(original.id) == edited


@pytest.mark.parametrize("description", [None, "Replace damaged boards"])
def test_unchanged_values_do_not_save_or_change_timestamp(
    tmp_path: Path, monkeypatch: MonkeyPatch, description: str | None
) -> None:
    """Assigning existing project values leaves storage and timestamps alone."""
    def unexpected_save(project: Project) -> None:
        """Fail if an unchanged project is written to storage."""
        pytest.fail("An unchanged project should not be saved")

    database = tmp_path / "heap.sqlite"
    monkeypatch.setattr(project_operator, "current_time", lambda: CREATED)
    with SQLiteProjectStore(database) as store:
        projects = ProjectOperator(store)
        original = projects.create("Repair the fence", description)
        monkeypatch.setattr(project_operator, "current_time", lambda: EDITED)
        monkeypatch.setattr(store, "save", unexpected_save)
        assert projects.set_name(original.id, original.name) == original
        assert projects.set_description(original.id, description) == original

    with SQLiteProjectStore(database) as store:
        assert ProjectOperator(store).get(original.id) == original


def test_editing_missing_project_raises_key_error(tmp_path: Path) -> None:
    """An edit rejects an unknown ID rather than creating a project."""
    missing_id = uuid4()
    database = tmp_path / "heap.sqlite"
    with SQLiteProjectStore(database) as store:
        projects = ProjectOperator(store)
        with pytest.raises(KeyError) as name_error:
            projects.set_name(missing_id, "New name")
        assert name_error.value.args == (missing_id,)
        with pytest.raises(KeyError) as description_error:
            projects.set_description(missing_id, "New description")
        assert description_error.value.args == (missing_id,)

    with SQLiteProjectStore(database) as store:
        assert ProjectOperator(store).get(missing_id) is None
