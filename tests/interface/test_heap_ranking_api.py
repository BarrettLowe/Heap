from __future__ import annotations

import json
from datetime import date, datetime
from pathlib import Path
from uuid import UUID

import pytest
from fastapi.testclient import TestClient

from heap.interface.app import create_app
from heap.logic.duration import Duration
from heap.logic.priority import Priority
from heap.logic.task import Task, TaskStatus
from heap.persistence.sqlite_task_store import SQLiteTaskStore


@pytest.mark.parametrize(
    "query",
    [
        "",
        "?local_date=2026-02-30",
        "?local_date=2026-1-02",
        "?local_date=2026-01-01&local_date=2026-01-02",
    ],
)
def test_heap_requires_one_valid_canonical_date(tmp_path: Path, query: str) -> None:
    """Reject a missing, malformed, or repeated local date query."""
    with TestClient(create_app(tmp_path / "heap.sqlite")) as client:
        response = client.get("/api/v1/heap" + query)

    assert response.status_code == 422
    assert response.json()["error"]["code"] == "invalid_request"
    assert response.json()["error"]["fields"][0]["field"] == "local_date"


def test_heap_returns_shared_fixture_order_for_each_local_date(
    tmp_path: Path,
) -> None:
    """Serve the shared 8-task ordering fixture without changing stored snapshots."""
    fixture_path = Path(__file__).parents[2] / "docs" / "heap-ranking-fixture.json"
    fixture = json.loads(fixture_path.read_text())
    database = tmp_path / "heap.sqlite"

    def parse_timestamp(value: str) -> datetime:
        """Parse the fixture's canonical UTC timestamp into an aware datetime."""
        return datetime.fromisoformat(value.replace("Z", "+00:00"))

    fixture_tasks = [
        Task(
            id=UUID(item["id"]),
            title=item["label"],
            status=TaskStatus.ON_HEAP,
            created_at=parse_timestamp(item["on_heap_since"]),
            updated_at=parse_timestamp(item["on_heap_since"]),
            priority=Priority(item["priority"]),
            duration=Duration.THIRTY_MINUTES,
            on_heap_since=parse_timestamp(item["on_heap_since"]),
            externally_blocked=item["externally_blocked"],
            due_date=date.fromisoformat(item["due_date"]) if item["due_date"] else None,
        )
        for item in fixture["tasks"]
    ]
    with SQLiteTaskStore(database) as store:
        store.save_many(fixture_tasks)
        before = [store.get(task.id) for task in fixture_tasks]

    with TestClient(create_app(database)) as client:
        responses = [
            client.get("/api/v1/heap", params={"local_date": case["today"]})
            for case in fixture["cases"]
        ]

    assert all(response.status_code == 200 for response in responses)
    for response, case in zip(responses, fixture["cases"], strict=True):
        assert [item["id"] for item in response.json()["items"]] == case["expected_ids"]
    assert len(responses[0].json()["items"]) == len(fixture["tasks"])
    assert any(item["externally_blocked"] for item in responses[0].json()["items"])
    with SQLiteTaskStore(database) as store:
        assert [store.get(task.id) for task in fixture_tasks] == before
