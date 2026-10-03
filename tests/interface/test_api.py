from __future__ import annotations

import json
import sqlite3
import threading
from concurrent.futures import ThreadPoolExecutor
from datetime import UTC, datetime
from pathlib import Path
from uuid import UUID

import pytest
from fastapi.testclient import TestClient
from pytest import MonkeyPatch

from heap.interface.app import create_app
from heap.logic import task_operator
from heap.persistence.sqlite_task_store import SQLiteTaskStore


def client_for(database: Path, cors_origins: list[str] | None = None) -> TestClient:
    """Build a test client backed by the requested SQLite file."""
    return TestClient(
        create_app(database, cors_origins or []), raise_server_exceptions=False
    )


def test_health_waits_for_database_initialization(tmp_path: Path) -> None:
    """The health response is available after opening SQLite."""
    with client_for(tmp_path / "heap.sqlite") as client:
        response = client.get("/healthz")

    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_capture_returns_saved_task_with_contract_utc_format(
    tmp_path: Path, monkeypatch: MonkeyPatch
) -> None:
    """Capture trims the title and returns the saved inbox snapshot."""
    now = datetime(2026, 10, 3, 12, 34, 56, 123456, tzinfo=UTC)
    monkeypatch.setattr(task_operator, "current_time", lambda: now)
    database = tmp_path / "heap.sqlite"

    with client_for(database) as client:
        response = client.post("/api/v1/tasks", json={"title": "  Wash driveway  "})

    assert response.status_code == 201
    body = response.json()
    assert set(body) == {"id", "title", "status", "created_at", "updated_at"}
    assert body["title"] == "Wash driveway"
    assert body["status"] == "inbox"
    assert str(UUID(body["id"])) == body["id"]
    assert body["created_at"] == "2026-10-03T12:34:56.123456Z"
    assert body["updated_at"] == body["created_at"]

    with client_for(database) as client:
        assert client.get("/api/v1/inbox").json() == {"items": [body]}


def test_inbox_empty_and_method_not_allowed_include_contract_error(
    tmp_path: Path,
) -> None:
    """Inbox starts empty and unsupported methods use the shared error shape."""
    with client_for(tmp_path / "heap.sqlite") as client:
        assert client.get("/api/v1/inbox").json() == {"items": []}
        response = client.post("/api/v1/inbox", json={})

    assert response.status_code == 405
    assert response.json()["error"]["code"] == "method_not_allowed"
    assert response.json()["error"]["fields"] == []
    assert response.headers["allow"]


def test_unknown_path_has_contract_not_found_error(tmp_path: Path) -> None:
    """Unknown paths are returned using the common API error format."""
    with client_for(tmp_path / "heap.sqlite") as client:
        response = client.get("/unknown")

    assert response.status_code == 404
    assert response.json() == {
        "error": {
            "code": "not_found",
            "message": "Not found.",
            "fields": [],
        }
    }


def test_invalid_json_and_invalid_titles_do_not_write(
    tmp_path: Path,
) -> None:
    """Malformed or invalid capture input is rejected without saving."""
    database = tmp_path / "heap.sqlite"
    with client_for(database) as client:
        malformed = client.post(
            "/api/v1/tasks",
            content=b'{"title":"do-not-echo"',
            headers={"Content-Type": "application/json"},
        )
        blank = client.post("/api/v1/tasks", json={"title": "  "})
        wrong_type = client.post("/api/v1/tasks", json={"title": 12})
        extra = client.post("/api/v1/tasks", json={"title": "valid", "id": "x"})
        missing = client.post("/api/v1/tasks", json={})
        listed = client.get("/api/v1/inbox")

    for response in (malformed, blank, wrong_type, extra, missing):
        assert response.status_code == 422
        assert response.json()["error"]["code"] == "invalid_request"
        assert isinstance(response.json()["error"]["fields"], list)
    assert listed.json() == {"items": []}
    assert "do-not-echo" not in json.dumps(malformed.json())


def test_unparseable_json_values_are_rejected_without_writing(
    tmp_path: Path,
) -> None:
    """Parser limits and invalid Unicode are client errors, not storage errors."""
    with client_for(tmp_path / "heap.sqlite") as client:
        oversized_integer = client.post(
            "/api/v1/tasks",
            content=b'{"title":' + b"1" * 5000 + b"}",
            headers={"Content-Type": "application/json"},
        )
        invalid_unicode = client.post(
            "/api/v1/tasks",
            content=b'{"title":"\\ud800"}',
            headers={"Content-Type": "application/json"},
        )
        listed = client.get("/api/v1/inbox")

    for response in (oversized_integer, invalid_unicode):
        assert response.status_code == 422
        assert response.json()["error"]["code"] == "invalid_request"
    assert listed.json() == {"items": []}


def test_non_json_capture_is_unsupported_media_type(tmp_path: Path) -> None:
    """Capture requires the JSON media type."""
    with client_for(tmp_path / "heap.sqlite") as client:
        response = client.post(
            "/api/v1/tasks",
            content="title=valid",
            headers={"Content-Type": "text/plain"},
        )
        listed = client.get("/api/v1/inbox")

    assert response.status_code == 415
    assert listed.json() == {"items": []}
    assert response.json()["error"]["code"] == "unsupported_media_type"
    assert response.json()["error"]["fields"] == []


def test_cors_allows_origin_preflight_and_keeps_headers_on_errors(
    tmp_path: Path,
) -> None:
    """Allowed web origins receive CORS headers on preflight and API errors."""
    origin = "https://heap.example"
    with client_for(tmp_path / "heap.sqlite", [origin]) as client:
        preflight = client.options(
            "/api/v1/tasks",
            headers={
                "Origin": origin,
                "Access-Control-Request-Method": "POST",
                "Access-Control-Request-Headers": "content-type",
            },
        )
        error = client.post(
            "/api/v1/tasks", json={"title": " "}, headers={"Origin": origin}
        )

    assert preflight.status_code == 200
    assert preflight.headers["access-control-allow-origin"] == origin
    assert "POST" in preflight.headers["access-control-allow-methods"]
    assert error.status_code == 422
    assert error.headers["access-control-allow-origin"] == origin


def test_disallowed_origin_does_not_receive_cors_permission(tmp_path: Path) -> None:
    """Unconfigured origins are not granted browser access."""
    with client_for(tmp_path / "heap.sqlite", ["https://allowed.example"]) as client:
        response = client.get(
            "/api/v1/inbox", headers={"Origin": "https://other.example"}
        )

    assert "access-control-allow-origin" not in response.headers


def test_storage_errors_are_logged_and_hidden_from_client(
    tmp_path: Path,
    caplog: pytest.LogCaptureFixture,
) -> None:
    """SQLite write failures return a generic error without database details."""
    database = tmp_path / "heap.sqlite"
    with SQLiteTaskStore(database):
        pass
    with sqlite3.connect(database) as connection:
        connection.execute(
            """
            CREATE TRIGGER fail_task_insert BEFORE INSERT ON tasks
            BEGIN SELECT RAISE(ABORT, 'private database detail'); END
            """
        )

    with client_for(database, ["https://heap.example"]) as client:
        response = client.post(
            "/api/v1/tasks",
            json={"title": "valid"},
            headers={"Origin": "https://heap.example"},
        )

    assert response.status_code == 500
    assert response.json() == {
        "error": {
            "code": "internal_error",
            "message": "An unexpected error occurred.",
            "fields": [],
        }
    }
    assert "private database detail" not in response.text
    assert "private database detail" in caplog.text
    assert response.headers["access-control-allow-origin"] == "https://heap.example"


def test_concurrent_capture_requests_are_serialized(tmp_path: Path) -> None:
    """Concurrent clients can capture without crossing the SQLite thread boundary."""
    with client_for(tmp_path / "heap.sqlite") as client:
        barrier = threading.Barrier(5)

        def capture(index: int) -> int:
            """Wait for the other workers, then send one capture."""
            barrier.wait()
            return client.post(
                "/api/v1/tasks", json={"title": f"Task {index}"}
            ).status_code

        with ThreadPoolExecutor(max_workers=5) as executor:
            results = list(executor.map(capture, range(5)))
        listed = client.get("/api/v1/inbox")

    assert results == [201] * 5
    assert len(listed.json()["items"]) == 5


def test_health_is_not_available_when_database_cannot_initialize(
    tmp_path: Path,
) -> None:
    """A database path that is a file cannot be mistaken for a healthy service."""
    database = tmp_path / "not-a-directory"
    database.write_text("not a directory")
    with pytest.raises(OSError), client_for(database / "heap.sqlite"):
        pass
