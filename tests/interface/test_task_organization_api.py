from __future__ import annotations

import json
import sqlite3
from concurrent.futures import ThreadPoolExecutor
from datetime import UTC, datetime
from pathlib import Path
from uuid import UUID, uuid4

import pytest
from fastapi.testclient import TestClient
from pytest import MonkeyPatch

from heap.interface.app import create_app
from heap.logic import task_operator
from heap.logic.task import Task
from heap.logic.task_operator import TaskOperator
from heap.persistence.sqlite_task_store import SQLiteTaskStore

NOW = datetime(2026, 10, 3, 12, 34, 56, 123456, tzinfo=UTC)
LATER = datetime(2026, 10, 4, 9, 0, 0, 123456, tzinfo=UTC)
REENTERED = datetime(2026, 10, 5, 9, 0, 0, 123456, tzinfo=UTC)


def client_for(database: Path, cors_origins: list[str] | None = None) -> TestClient:
    """Build a client backed by a temporary SQLite database."""
    return TestClient(
        create_app(database, cors_origins or []), raise_server_exceptions=False
    )


def organization_body(
    updated_at: str,
    *,
    title: str = "Repair the fence",
    priority: int | None = 2,
    duration: int | None = 30,
    waiting: bool = False,
) -> dict[str, object]:
    """Build a complete organization request with a saved comparison token."""
    return {
        "title": title,
        "priority": priority,
        "duration_minutes": duration,
        "externally_blocked": waiting,
        "project_id": None,
        "expected_updated_at": updated_at,
    }


def test_detail_lists_and_atomic_save_return_exact_snapshots(
    tmp_path: Path,
    monkeypatch: MonkeyPatch,
) -> None:
    """Capture stays compatible while bulk lists/detail carry required metadata."""
    monkeypatch.setattr(task_operator, "current_time", lambda: NOW)
    with client_for(tmp_path / "heap.sqlite") as client:
        captured = client.post(
            "/api/v1/tasks", json={"title": "Repair the fence"}
        ).json()
        assert set(captured) == {"id", "title", "status", "created_at", "updated_at"}
        path = f"/api/v1/tasks/{captured['id']}"
        inbox_item = {
            **captured,
            "priority": None,
            "duration_minutes": None,
            "externally_blocked": False,
            "project_id": None,
        }
        assert client.get("/api/v1/inbox").json() == {"items": [inbox_item]}
        assert client.get(path).json() == {**inbox_item, "on_heap_since": None}
        assert client.get("/api/v1/heap").json() == {"items": []}
        monkeypatch.setattr(task_operator, "current_time", lambda: LATER)
        response = client.put(
            path + "/organization",
            json=organization_body(captured["updated_at"], waiting=True),
        )
        assert response.status_code == 200
        saved = response.json()
        assert saved == {
            **captured,
            "status": "on_heap",
            "updated_at": "2026-10-04T09:00:00.123456Z",
            "priority": 2,
            "duration_minutes": 30,
            "externally_blocked": True,
            "project_id": None,
            "on_heap_since": "2026-10-04T09:00:00.123456Z",
        }
        assert client.get(path).json() == saved
        assert client.get("/api/v1/heap").json() == {"items": [saved]}
        assert client.get("/api/v1/inbox").json() == {"items": []}


def test_heap_api_names_preserve_existing_database_format_after_restart(
    tmp_path: Path,
    monkeypatch: MonkeyPatch,
) -> None:
    """Heap API vocabulary round-trips without renaming stored columns or values."""
    database = tmp_path / "heap.sqlite"
    monkeypatch.setattr(task_operator, "current_time", lambda: NOW)
    with client_for(database) as client:
        captured = client.post(
            "/api/v1/tasks", json={"title": "Repair the fence"}
        ).json()
        path = f"/api/v1/tasks/{captured['id']}"
        monkeypatch.setattr(task_operator, "current_time", lambda: LATER)
        response = client.put(
            path + "/organization",
            json=organization_body(captured["updated_at"], waiting=True),
        )
        assert response.status_code == 200
        saved = response.json()
        assert saved["status"] == "on_heap"
        assert saved["on_heap_since"] == "2026-10-04T09:00:00.123456Z"
        assert "on_deck_since" not in saved
        assert client.get("/api/v1/on-deck").status_code == 404

    with sqlite3.connect(database) as connection:
        stored = connection.execute(
            "SELECT status, on_deck_since FROM tasks WHERE id = ?", (captured["id"],)
        ).fetchone()
        assert stored == ("on_deck", LATER.isoformat())
        columns = {row[1] for row in connection.execute("PRAGMA table_info(tasks)")}
        assert "on_deck_since" in columns
        assert "on_heap_since" not in columns

    with client_for(database) as client:
        assert client.get(path).json() == saved
        assert client.get("/api/v1/heap").json() == {"items": [saved]}
        assert client.get("/api/v1/inbox").json() == {"items": []}
        unchanged = client.put(
            path + "/organization",
            json=organization_body(saved["updated_at"], waiting=True),
        )
        assert unchanged.status_code == 200
        assert unchanged.json() == saved


@pytest.mark.parametrize(
    ("priority", "duration"), [(None, 30), (2, None), (None, None)]
)
def test_nullable_requirements_clear_then_automatically_restore_with_new_age(
    tmp_path: Path,
    monkeypatch: MonkeyPatch,
    priority: int | None,
    duration: int | None,
) -> None:
    """Incomplete saves are valid; restored requirements automatically re-enter."""
    monkeypatch.setattr(task_operator, "current_time", lambda: NOW)
    with client_for(tmp_path / "heap.sqlite") as client:
        captured = client.post(
            "/api/v1/tasks", json={"title": "Repair the fence"}
        ).json()
        path = f"/api/v1/tasks/{captured['id']}/organization"
        saved = client.put(
            path, json=organization_body(captured["updated_at"], waiting=True)
        ).json()
        monkeypatch.setattr(task_operator, "current_time", lambda: LATER)
        cleared = client.put(
            path,
            json=organization_body(
                saved["updated_at"], priority=priority, duration=duration, waiting=True
            ),
        )
        assert cleared.status_code == 200
        snapshot = cleared.json()
        assert snapshot["status"] == "inbox"
        assert snapshot["on_heap_since"] is None
        assert snapshot["externally_blocked"] is True
        inbox = client.get("/api/v1/inbox").json()["items"]
        assert inbox == [
            {key: value for key, value in snapshot.items() if key != "on_heap_since"}
        ]
        monkeypatch.setattr(task_operator, "current_time", lambda: REENTERED)
        restored = client.put(
            path, json=organization_body(snapshot["updated_at"], waiting=True)
        ).json()
        assert restored["status"] == "on_heap"
        assert restored["on_heap_since"] == "2026-10-05T09:00:00.123456Z"


def test_flag_only_edits_preserve_age_and_no_op_reads_no_time(
    tmp_path: Path,
    monkeypatch: MonkeyPatch,
) -> None:
    """Waiting is edited atomically but does not independently alter placement."""
    monkeypatch.setattr(task_operator, "current_time", lambda: NOW)
    with client_for(tmp_path / "heap.sqlite") as client:
        captured = client.post(
            "/api/v1/tasks", json={"title": "Repair the fence"}
        ).json()
        path = f"/api/v1/tasks/{captured['id']}/organization"
        saved = client.put(path, json=organization_body(captured["updated_at"])).json()
        monkeypatch.setattr(task_operator, "current_time", lambda: LATER)
        waiting = client.put(
            path, json=organization_body(saved["updated_at"], waiting=True)
        ).json()
        assert waiting["on_heap_since"] == saved["on_heap_since"]
        assert waiting["status"] == "on_heap"
        cleared = client.put(path, json=organization_body(waiting["updated_at"])).json()
        assert cleared["on_heap_since"] == saved["on_heap_since"]
        assert cleared["externally_blocked"] is False

        def unexpected_time() -> datetime:
            """Fail if an unchanged submit requests operation time."""
            pytest.fail("No-op read time")

        monkeypatch.setattr(task_operator, "current_time", unexpected_time)
        unchanged = client.put(path, json=organization_body(cleared["updated_at"]))
        assert unchanged.status_code == 200
        assert unchanged.json() == cleared


def test_stale_update_is_conflict_without_overwriting_saved_task(
    tmp_path: Path,
    monkeypatch: MonkeyPatch,
) -> None:
    """A stale token leaves every newer editable field intact."""
    monkeypatch.setattr(task_operator, "current_time", lambda: NOW)
    with client_for(tmp_path / "heap.sqlite") as client:
        captured = client.post(
            "/api/v1/tasks", json={"title": "Repair the fence"}
        ).json()
        path = f"/api/v1/tasks/{captured['id']}"
        monkeypatch.setattr(task_operator, "current_time", lambda: LATER)
        saved = client.put(
            path + "/organization",
            json=organization_body(
                captured["updated_at"], title="Newer edit", waiting=True
            ),
        )
        stale = client.put(
            path + "/organization",
            json=organization_body(captured["updated_at"], title="Stale edit"),
        )
        assert stale.status_code == 409
        assert stale.json()["error"]["code"] == "task_conflict"
        assert stale.json()["error"]["fields"] == []
        assert client.get(path).json() == saved.json()


def test_completed_task_rejects_unchanged_and_stale_organization(
    tmp_path: Path,
) -> None:
    """Completed tasks are readable and reject writes before stale comparison."""
    database = tmp_path / "heap.sqlite"
    with client_for(database) as client:
        captured = client.post(
            "/api/v1/tasks", json={"title": "Repair the fence"}
        ).json()
    with SQLiteTaskStore(database) as store:
        TaskOperator(store).complete(UUID(captured["id"]))
    with client_for(database) as client:
        path = f"/api/v1/tasks/{captured['id']}"
        detail = client.get(path).json()
        for token in (detail["updated_at"], captured["updated_at"]):
            response = client.put(
                path + "/organization",
                json=organization_body(token, priority=None, duration=None),
            )
            assert response.status_code == 409
            assert response.json()["error"]["code"] == "task_completed"
            assert response.json()["error"]["fields"] == []
        assert client.get(path).json() == detail
        assert detail["status"] == "completed"


@pytest.mark.parametrize(
    ("change", "remove"),
    [
        ({"title": 12}, None),
        ({"title": " "}, None),
        ({"title": None}, None),
        ({"priority": True}, None),
        ({"priority": 2.0}, None),
        ({"priority": "2"}, None),
        ({"priority": 0}, None),
        ({"priority": 6}, None),
        ({"duration_minutes": True}, None),
        ({"duration_minutes": 30.0}, None),
        ({"duration_minutes": "30"}, None),
        ({"duration_minutes": 10}, None),
        ({"externally_blocked": None}, None),
        ({"externally_blocked": 0}, None),
        ({"externally_blocked": "false"}, None),
        ({"externally_blocked": 1.0}, None),
        ({"move_to_on_deck": False}, None),
        ({"move_to_on_deck": True}, None),
        ({"move_to_on_deck": None}, None),
        ({"extra": "field"}, None),
        ({"\ud800": "invalid Unicode field name"}, None),
        ({}, "title"),
        ({}, "priority"),
        ({}, "duration_minutes"),
        ({}, "externally_blocked"),
        ({}, "expected_updated_at"),
        ({"expected_updated_at": None}, None),
        ({"expected_updated_at": 123}, None),
        ({"expected_updated_at": "2026-10-03T12:34:56Z"}, None),
        ({"expected_updated_at": "2026-10-03T12:34:56.123Z"}, None),
        ({"expected_updated_at": "2026-10-03T12:34:56.123456+00:00"}, None),
        ({"expected_updated_at": "2026-99-03T12:34:56.123456Z"}, None),
    ],
)
def test_invalid_organization_bodies_do_not_change_snapshot(
    tmp_path: Path,
    change: dict[str, object],
    remove: str | None,
) -> None:
    """Strict fields, obsolete move intention and malformed tokens are rejected."""
    with client_for(tmp_path / "heap.sqlite") as client:
        captured = client.post(
            "/api/v1/tasks", json={"title": "Repair the fence"}
        ).json()
        path = f"/api/v1/tasks/{captured['id']}"
        before = client.get(path).json()
        body = organization_body(captured["updated_at"])
        body.update(change)
        if remove is not None:
            body.pop(remove)
        response = client.put(
            path + "/organization",
            content=json.dumps(body).encode("utf-8"),
            headers={"Content-Type": "application/json"},
        )
        assert response.status_code == 422
        assert response.json()["error"]["code"] == "invalid_request"
        assert isinstance(response.json()["error"]["fields"], list)
        assert client.get(path).json() == before


def test_invalid_json_and_unicode_do_not_write_or_echo_request(tmp_path: Path) -> None:
    """Malformed/limited parser input and invalid Unicode fail before saving."""
    with client_for(tmp_path / "heap.sqlite") as client:
        captured = client.post(
            "/api/v1/tasks", json={"title": "Repair the fence"}
        ).json()
        path = f"/api/v1/tasks/{captured['id']}"
        before = client.get(path).json()
        invalid_unicode = organization_body(captured["updated_at"])
        invalid_unicode["title"] = "\ud800"
        bodies = [
            b'{"title":"do-not-echo"',
            b'{"title":"\xff"}',
            b'{"title":' + b"1" * 5000 + b"}",
            b"[" * 2000 + b"0" + b"]" * 2000,
            json.dumps(invalid_unicode).encode(),
        ]
        for body in bodies:
            response = client.put(
                path + "/organization",
                content=body,
                headers={"Content-Type": "application/json"},
            )
            assert response.status_code == 422
            assert response.json()["error"]["code"] == "invalid_request"
            assert "do-not-echo" not in response.text
        assert client.get(path).json() == before


def test_bad_ids_and_missing_tasks_use_contract_errors(tmp_path: Path) -> None:
    """Both routes distinguish malformed UUIDs from missing saved tasks."""
    with client_for(tmp_path / "heap.sqlite") as client:
        for task_id, expected in (("not-a-uuid", 422), (str(uuid4()), 404)):
            path = f"/api/v1/tasks/{task_id}"
            for response in (
                client.get(path),
                client.put(
                    path + "/organization",
                    json=organization_body("2026-10-03T12:34:56.123456Z"),
                ),
            ):
                assert response.status_code == expected
                assert response.json()["error"]["code"] == (
                    "invalid_request" if expected == 422 else "not_found"
                )


@pytest.mark.parametrize(
    "form",
    [
        "canonical",
        "uppercase",
        "unhyphenated",
        "braced",
        "urn",
        "extra_hyphens",
        "repeated_hyphens",
    ],
)
def test_task_paths_require_exact_canonical_uuid_before_lookup_or_write(
    tmp_path: Path,
    monkeypatch: MonkeyPatch,
    form: str,
) -> None:
    """Noncanonical UUID paths reject GET/PUT without lookup, time, or writes."""
    database = tmp_path / "heap.sqlite"
    origin = "https://heap.example"
    monkeypatch.setattr(task_operator, "current_time", lambda: NOW)
    monkeypatch.setattr(
        task_operator, "uuid4", lambda: UUID("d4be2fc9-49b7-46a6-9981-1f063eed03ea")
    )
    with client_for(database, [origin]) as client:
        captured = client.post(
            "/api/v1/tasks", json={"title": "Repair the fence"}
        ).json()
        canonical_id = captured["id"]
        forms = {
            "canonical": canonical_id,
            "uppercase": canonical_id.upper(),
            "unhyphenated": canonical_id.replace("-", ""),
            "braced": "{" + canonical_id + "}",
            "urn": "urn:uuid:" + canonical_id,
            "extra_hyphens": "--" + canonical_id + "--",
            "repeated_hyphens": canonical_id.replace("-", "--"),
        }
        path = f"/api/v1/tasks/{forms[form]}"
        with SQLiteTaskStore(database) as store:
            before = store.get(UUID(canonical_id))
        reads = 0
        writes = 0
        lookups = 0
        real_save = SQLiteTaskStore.save
        real_get = TaskOperator.get

        def read_time() -> datetime:
            """Count operation clock reads after capture."""
            nonlocal reads
            reads += 1
            return LATER

        def record_save(store: SQLiteTaskStore, task: Task) -> None:
            """Count actual snapshot saves after capture."""
            nonlocal writes
            writes += 1
            real_save(store, task)

        def record_lookup(tasks: TaskOperator, task_id: UUID) -> Task:
            """Count lookups so invalid paths cannot reach comparison checks."""
            nonlocal lookups
            lookups += 1
            return real_get(tasks, task_id)

        monkeypatch.setattr(task_operator, "current_time", read_time)
        monkeypatch.setattr(SQLiteTaskStore, "save", record_save)
        monkeypatch.setattr(TaskOperator, "get", record_lookup)
        fetched = client.get(path, headers={"Origin": origin})
        saved = client.put(
            path + "/organization",
            json=organization_body(
                captured["updated_at"], title="Submitted edit", waiting=True
            ),
            headers={"Origin": origin},
        )
        if form == "canonical":
            assert fetched.status_code == saved.status_code == 200
            assert reads == writes == 1
            assert saved.json()["title"] == "Submitted edit"
        else:
            for response in (fetched, saved):
                assert response.status_code == 422
                assert response.json() == {
                    "error": {
                        "code": "invalid_request",
                        "message": "Request validation failed.",
                        "fields": [{"field": "task_id", "message": "Must be a UUID."}],
                    }
                }
                assert response.headers["access-control-allow-origin"] == origin
                assert "Submitted edit" not in response.text
            assert reads == writes == lookups == 0

    with SQLiteTaskStore(database) as store:
        reloaded = store.get(UUID(canonical_id))
        if form == "canonical":
            assert reloaded is not None
            assert reloaded.title == "Submitted edit"
        else:
            assert reloaded == before


def test_put_requires_json_and_cors_covers_preflight_and_errors(tmp_path: Path) -> None:
    """Allowed origins receive PUT preflight and API error headers."""
    origin = "https://heap.example"
    with client_for(tmp_path / "heap.sqlite", [origin]) as client:
        captured = client.post(
            "/api/v1/tasks", json={"title": "Repair the fence"}
        ).json()
        path = f"/api/v1/tasks/{captured['id']}/organization"
        preflight = client.options(
            path,
            headers={
                "Origin": origin,
                "Access-Control-Request-Method": "PUT",
                "Access-Control-Request-Headers": "content-type",
            },
        )
        assert preflight.status_code == 200
        assert "PUT" in preflight.headers["access-control-allow-methods"]
        invalid = client.put(
            path,
            json=organization_body(captured["updated_at"], title=" "),
            headers={"Origin": origin},
        )
        unsupported = client.put(
            path,
            content="not json",
            headers={"Content-Type": "text/plain", "Origin": origin},
        )
        assert invalid.status_code == 422
        assert unsupported.status_code == 415
        assert unsupported.json()["error"]["code"] == "unsupported_media_type"
        for response in (preflight, invalid, unsupported):
            assert response.headers["access-control-allow-origin"] == origin


def test_failed_put_returns_generic_500_with_cors_and_preserves_snapshot(
    tmp_path: Path,
) -> None:
    """Storage failure is hidden from clients and leaves all fields unchanged."""
    database = tmp_path / "heap.sqlite"
    with client_for(database) as client:
        captured = client.post(
            "/api/v1/tasks", json={"title": "Repair the fence"}
        ).json()
        path = f"/api/v1/tasks/{captured['id']}"
        before = client.get(path).json()
    with sqlite3.connect(database) as connection:
        connection.execute("""
            CREATE TRIGGER reject_update BEFORE UPDATE ON tasks
            BEGIN SELECT RAISE(ABORT, 'private update details'); END
        """)
    origin = "https://heap.example"
    with client_for(database, [origin]) as client:
        failed = client.put(
            path + "/organization",
            json=organization_body(
                captured["updated_at"], title="Changed", waiting=True
            ),
            headers={"Origin": origin},
        )
        assert failed.status_code == 500
        assert failed.json()["error"]["code"] == "internal_error"
        assert failed.headers["access-control-allow-origin"] == origin
        assert "private update details" not in failed.text
        assert client.get(path).json() == before
    with client_for(database) as client:
        assert client.get(path).json() == before


def test_competing_puts_compare_tokens_inside_whole_operation_lock(
    tmp_path: Path,
    monkeypatch: MonkeyPatch,
) -> None:
    """One competing edit succeeds; the other sees its saved token and conflicts."""
    monkeypatch.setattr(task_operator, "current_time", lambda: NOW)
    with client_for(tmp_path / "heap.sqlite") as client:
        captured = client.post(
            "/api/v1/tasks", json={"title": "Repair the fence"}
        ).json()
        monkeypatch.setattr(task_operator, "current_time", lambda: LATER)

        def save(title: str) -> int:
            """Submit one competing edit with the same original token."""
            return client.put(
                f"/api/v1/tasks/{captured['id']}/organization",
                json=organization_body(captured["updated_at"], title=title),
            ).status_code

        with ThreadPoolExecutor(max_workers=2) as executor:
            statuses = list(executor.map(save, ["First", "Second"]))
        assert sorted(statuses) == [200, 409]
        assert len(client.get("/api/v1/heap").json()["items"]) == 1
