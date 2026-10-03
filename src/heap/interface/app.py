from __future__ import annotations

import json
import logging
import os
import threading
from contextlib import asynccontextmanager
from datetime import UTC
from pathlib import Path
from urllib.parse import urlsplit
from uuid import UUID

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from pydantic import BaseModel, ConfigDict, StrictStr, ValidationError, field_validator

from heap.logic.task import Task
from heap.logic.task_operator import TaskOperator
from heap.persistence.sqlite_task_store import SQLiteTaskStore

logger = logging.getLogger(__name__)


class CaptureRequest(BaseModel):
    """Validate and trim a title-only task capture request."""

    model_config = ConfigDict(extra="forbid")

    title: StrictStr

    @field_validator("title")
    @classmethod
    def trim_title(cls, title: str) -> str:
        """Reject blank or invalid Unicode titles and trim the rest."""
        try:
            title.encode("utf-8")
        except UnicodeEncodeError as error:
            raise ValueError("Must contain valid Unicode.") from error
        trimmed = title.strip()
        if not trimmed:
            raise ValueError("Must not be blank.")
        return trimmed


def _error_response(
    status_code: int,
    code: str,
    message: str,
    fields: list[dict[str, str]] | None = None,
    headers: dict[str, str] | None = None,
) -> JSONResponse:
    """Build an API error using the common response shape."""
    return JSONResponse(
        status_code=status_code,
        content={
            "error": {
                "code": code,
                "message": message,
                "fields": fields or [],
            }
        },
        headers=headers,
    )


def _serialize_task(task: Task) -> dict[str, str]:
    """Return only the inbox task fields exposed by the HTTP contract."""
    return {
        "id": str(UUID(str(task.id))),
        "title": task.title,
        "status": task.status.value,
        "created_at": task.created_at.astimezone(UTC)
        .isoformat(timespec="microseconds")
        .replace("+00:00", "Z"),
        "updated_at": task.updated_at.astimezone(UTC)
        .isoformat(timespec="microseconds")
        .replace("+00:00", "Z"),
    }


def _load_cors_origins() -> list[str]:
    """Read and validate the explicit CORS origin list from the environment."""
    configured = json.loads(os.environ.get("HEAP_CORS_ORIGINS", "[]"))
    if not isinstance(configured, list) or any(
        not isinstance(item, str) for item in configured
    ):
        raise ValueError("HEAP_CORS_ORIGINS must be a JSON list of origins")
    for origin in configured:
        parsed = urlsplit(origin)
        if (
            origin == "*"
            or parsed.scheme not in {"http", "https"}
            or not parsed.netloc
            or parsed.username is not None
            or parsed.password is not None
            or parsed.path
            or parsed.query
            or parsed.fragment
        ):
            raise ValueError("HEAP_CORS_ORIGINS entries must be HTTP(S) origins")
    return configured


def create_app(
    database_path: Path | None = None,
    cors_origins: list[str] | None = None,
) -> CORSMiddleware:
    """Create the HTTP app with a SQLite database and explicit browser origins."""
    path = database_path or Path(
        os.environ.get("HEAP_DATABASE_PATH", "/data/heap.sqlite")
    )
    origins = _load_cors_origins() if cors_origins is None else cors_origins
    if "*" in origins:
        raise ValueError("CORS wildcard origins are not allowed")
    operation_lock = threading.RLock()

    @asynccontextmanager
    async def lifespan(application: FastAPI):
        """Open and close SQLite on the application event-loop thread."""
        path.parent.mkdir(parents=True, exist_ok=True)
        with SQLiteTaskStore(path) as store:
            application.state.tasks = TaskOperator(store)
            application.state.operation_lock = operation_lock
            yield

    application = FastAPI(
        lifespan=lifespan,
        docs_url=None,
        redoc_url=None,
        openapi_url=None,
        redirect_slashes=False,
    )

    @application.exception_handler(404)
    async def not_found_handler(request: Request, error: Exception) -> JSONResponse:
        """Return the contract error for unknown paths."""
        return _error_response(404, "not_found", "Not found.")

    @application.exception_handler(405)
    async def method_not_allowed_handler(
        request: Request, error: Exception
    ) -> JSONResponse:
        """Return the contract error and preserve the Allow response header."""
        headers = getattr(error, "headers", None)
        return _error_response(
            405, "method_not_allowed", "Method not allowed.", headers=headers
        )

    @application.exception_handler(Exception)
    async def unexpected_error_handler(
        request: Request, error: Exception
    ) -> JSONResponse:
        """Log unexpected details while returning a generic client error."""
        logger.exception("Unexpected API failure", exc_info=error)
        return _error_response(500, "internal_error", "An unexpected error occurred.")

    @application.get("/healthz")
    async def health() -> dict[str, str]:
        """Report healthy only after the SQLite store has opened."""
        return {"status": "ok"}

    @application.get("/api/v1/inbox")
    async def list_inbox(request: Request) -> dict[str, list[dict[str, str]]]:
        """Return the current saved inbox using the authoritative operation."""
        with request.app.state.operation_lock:
            tasks = request.app.state.tasks.list_inbox()
        return {"items": [_serialize_task(task) for task in tasks]}

    @application.post("/api/v1/tasks", status_code=201, response_model=None)
    async def capture(request: Request) -> JSONResponse | dict[str, str]:
        """Validate, save, and return a task title-only inbox snapshot."""
        content_type = (
            request.headers.get("content-type", "").split(";", 1)[0].strip().lower()
        )
        if content_type != "application/json":
            return _error_response(
                415, "unsupported_media_type", "Content-Type must be application/json."
            )
        try:
            body = await request.json()
        except (ValueError, RecursionError):
            return _error_response(
                422,
                "invalid_request",
                "Request validation failed.",
                [{"field": "", "message": "Invalid JSON."}],
            )
        try:
            payload = CaptureRequest.model_validate(body)
        except ValidationError as error:
            fields = [
                {
                    "field": ".".join(str(part) for part in issue["loc"]),
                    "message": (
                        str(issue["ctx"]["error"])
                        if issue["type"] == "value_error"
                        and isinstance(issue.get("ctx", {}).get("error"), ValueError)
                        else "Invalid value."
                    ),
                }
                for issue in error.errors()
            ]
            return _error_response(
                422, "invalid_request", "Request validation failed.", fields
            )
        with request.app.state.operation_lock:
            task = request.app.state.tasks.capture(payload.title)
        return _serialize_task(task)

    return CORSMiddleware(
        application,
        allow_origins=origins,
        allow_credentials=False,
        allow_methods=["GET", "POST"],
        allow_headers=["Content-Type"],
    )


app = create_app()
