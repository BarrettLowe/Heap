from __future__ import annotations

import json
import logging
import os
import threading
from contextlib import asynccontextmanager
from datetime import UTC, datetime
from pathlib import Path
from urllib.parse import urlsplit
from uuid import UUID

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from pydantic import (
    BaseModel,
    ConfigDict,
    StrictBool,
    StrictInt,
    StrictStr,
    ValidationError,
    field_validator,
)

from heap.logic.duration import Duration
from heap.logic.priority import Priority
from heap.logic.project import Project
from heap.logic.project_operator import ProjectOperator
from heap.logic.task import Task, TaskStatus
from heap.logic.task_operator import TaskOperator
from heap.persistence.sqlite_project_store import SQLiteProjectStore
from heap.persistence.sqlite_task_store import SQLiteTaskStore

logger = logging.getLogger(__name__)


def _trim_title(title: str) -> str:
    """Reject invalid Unicode or blank titles and remove surrounding whitespace."""
    try:
        title.encode("utf-8")
    except UnicodeEncodeError as error:
        raise ValueError("Must contain valid Unicode.") from error
    trimmed = title.strip()
    if not trimmed:
        raise ValueError("Must not be blank.")
    return trimmed


class CaptureRequest(BaseModel):
    """Validate and trim a title-only task capture request."""

    model_config = ConfigDict(extra="forbid")

    title: StrictStr

    @field_validator("title")
    @classmethod
    def trim_title(cls, title: str) -> str:
        """Reject blank or invalid Unicode titles and trim the rest."""
        return _trim_title(title)


class ProjectCreateRequest(BaseModel):
    """Validate a new project's name and optional description."""

    model_config = ConfigDict(extra="forbid")

    name: StrictStr
    description: StrictStr | None = None
    icon: StrictStr | None = None
    color: StrictStr | None = None

    @field_validator("name")
    @classmethod
    def trim_name(cls, name: str) -> str:
        """Reject blank or invalid Unicode names and trim the rest."""
        return _trim_title(name)

    @field_validator("description")
    @classmethod
    def validate_description(cls, description: str | None) -> str | None:
        """Reject invalid Unicode descriptions while preserving entered text."""
        if description is not None:
            try:
                description.encode("utf-8")
            except UnicodeEncodeError as error:
                raise ValueError("Must contain valid Unicode.") from error
        return description


class ProjectUpdateRequest(ProjectCreateRequest):
    """Validate replacement project fields, requiring description or null."""

    description: StrictStr | None


class OrganizationRequest(BaseModel):
    """Validate a complete task-organization replacement request."""

    model_config = ConfigDict(extra="forbid")

    title: StrictStr
    priority: StrictInt | None
    duration_minutes: StrictInt | None
    expected_updated_at: StrictStr
    externally_blocked: StrictBool
    project_id: StrictStr | None

    @field_validator("title")
    @classmethod
    def trim_title(cls, title: str) -> str:
        """Reject blank or invalid Unicode titles and trim the rest."""
        return _trim_title(title)

    @field_validator("priority")
    @classmethod
    def validate_priority(cls, value: int | None) -> int | None:
        """Accept only the 5 defined priority values or null."""
        if value is not None and value not in {priority.value for priority in Priority}:
            raise ValueError("Must be a priority from 1 through 5 or null.")
        return value

    @field_validator("duration_minutes")
    @classmethod
    def validate_duration(cls, value: int | None) -> int | None:
        """Accept only defined duration buckets or null."""
        if value is not None and value not in {
            duration.minutes
            for duration in Duration
            if duration is not Duration.UNKNOWN
        }:
            raise ValueError("Must be a supported duration or null.")
        return value

    @field_validator("project_id")
    @classmethod
    def validate_project_id(cls, value: str | None) -> str | None:
        """Accept only a canonical UUID or null for project assignment."""
        if value is not None and _parse_task_id(value) is None:
            raise ValueError("Must be a canonical project UUID or null.")
        return value

    @field_validator("expected_updated_at")
    @classmethod
    def validate_expected_updated_at(cls, value: str) -> str:
        """Require the canonical UTC timestamp format used by task responses."""
        try:
            parsed = datetime.strptime(value, "%Y-%m-%dT%H:%M:%S.%fZ").replace(
                tzinfo=UTC
            )
        except ValueError as error:
            raise ValueError("Must be a canonical UTC timestamp.") from error
        if _format_timestamp(parsed) != value:
            raise ValueError("Must be a canonical UTC timestamp.")
        return value


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


async def _read_json_body(
    request: Request,
) -> tuple[object | None, JSONResponse | None]:
    """Read a JSON request body or return its contract-shaped media/parser error."""
    content_type = (
        request.headers.get("content-type", "").split(";", 1)[0].strip().lower()
    )
    if content_type != "application/json":
        return None, _error_response(
            415, "unsupported_media_type", "Content-Type must be application/json."
        )
    try:
        body = await request.body()
        return json.loads(body.decode("utf-8")), None
    except (ValueError, RecursionError):
        return None, _error_response(
            422,
            "invalid_request",
            "Request validation failed.",
            [{"field": "", "message": "Invalid JSON."}],
        )


def _validation_error_response(error: ValidationError) -> JSONResponse:
    """Convert safe Pydantic field errors to the shared client-error envelope."""
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
    return _error_response(422, "invalid_request", "Request validation failed.", fields)


def _format_timestamp(value: datetime) -> str:
    """Return a timestamp in the contract's canonical UTC format."""
    return (
        value.astimezone(UTC).isoformat(timespec="microseconds").replace("+00:00", "Z")
    )


def _serialize_task(task: Task) -> dict[str, str]:
    """Return the original 5 fields exposed by title-only capture."""
    return {
        "id": str(UUID(str(task.id))),
        "title": task.title,
        "status": task.status.value,
        "created_at": _format_timestamp(task.created_at),
        "updated_at": _format_timestamp(task.updated_at),
    }


def _serialize_inbox_task(task: Task) -> dict[str, str | int | bool | None]:
    """Return bulk Inbox fields, including required organization and waiting data."""
    return {
        **_serialize_task(task),
        "priority": task.priority.value if task.priority is not None else None,
        "duration_minutes": task.duration.minutes,
        "externally_blocked": task.externally_blocked,
        "project_id": str(task.project_id) if task.project_id is not None else None,
    }


def _serialize_project(project: Project) -> dict[str, str | None]:
    """Return project fields used by list, detail, and edit responses."""
    return {
        "id": str(project.id),
        "name": project.name,
        "description": project.description,
        "status": project.status.value,
        "created_at": _format_timestamp(project.created_at),
        "updated_at": _format_timestamp(project.updated_at),
        "completed_at": (
            _format_timestamp(project.completed_at)
            if project.completed_at is not None
            else None
        ),
        "icon": project.icon,
        "color": project.color,
    }


def _serialize_task_detail(task: Task) -> dict[str, str | int | bool | None]:
    """Return the exact editable-task detail fields exposed by the contract."""
    return {
        **_serialize_inbox_task(task),
        "on_heap_since": (
            _format_timestamp(task.on_heap_since)
            if task.on_heap_since is not None
            else None
        ),
    }


def _parse_task_id(task_id: str) -> UUID | None:
    """Accept only an exact lowercase, hyphenated canonical task UUID."""
    try:
        parsed = UUID(task_id)
    except ValueError:
        return None
    return parsed if str(parsed) == task_id else None


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
        with (
            SQLiteTaskStore(path) as task_store,
            SQLiteProjectStore(path) as project_store,
        ):
            tasks = TaskOperator(task_store, project_store)
            projects = ProjectOperator(project_store)
            tasks.normalize_organization()
            application.state.tasks = tasks
            application.state.projects = projects
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
        """Report healthy only after opening SQLite and normalizing legacy tasks."""
        return {"status": "ok"}

    @application.get("/api/v1/projects")
    async def list_projects(request: Request) -> dict[str, list[dict[str, str | None]]]:
        """Return all projects in stable alphabetical order."""
        with request.app.state.operation_lock:
            projects = request.app.state.projects.list_all()
        return {"items": [_serialize_project(project) for project in projects]}

    @application.post("/api/v1/projects", status_code=201, response_model=None)
    async def create_project(request: Request) -> JSONResponse | dict[str, str | None]:
        """Validate and save a new project."""
        body, body_error = await _read_json_body(request)
        if body_error is not None:
            return body_error
        try:
            payload = ProjectCreateRequest.model_validate(body)
        except ValidationError as error:
            return _validation_error_response(error)
        with request.app.state.operation_lock:
            project = request.app.state.projects.create(
                payload.name, payload.description, payload.icon, payload.color
            )
        return _serialize_project(project)

    @application.get("/api/v1/projects/{project_id}/tasks", response_model=None)
    async def list_project_tasks(
        request: Request, project_id: str
    ) -> JSONResponse | dict[str, list[dict[str, str | int | bool | None]]]:
        """Return all project tasks, including completed tasks, oldest-first."""
        parsed_id = _parse_task_id(project_id)
        if parsed_id is None:
            return _error_response(
                422,
                "invalid_request",
                "Request validation failed.",
                [{"field": "project_id", "message": "Must be a UUID."}],
            )
        with request.app.state.operation_lock:
            if request.app.state.projects.get(parsed_id) is None:
                return _error_response(404, "not_found", "Not found.")
            tasks = request.app.state.tasks.list_for_project(parsed_id)
        return {"items": [_serialize_task_detail(task) for task in tasks]}

    @application.get("/api/v1/projects/{project_id}", response_model=None)
    async def get_project(
        request: Request, project_id: str
    ) -> JSONResponse | dict[str, str | None]:
        """Return one project or a contract-shaped not-found error."""
        parsed_id = _parse_task_id(project_id)
        if parsed_id is None:
            return _error_response(
                422,
                "invalid_request",
                "Request validation failed.",
                [{"field": "project_id", "message": "Must be a UUID."}],
            )
        with request.app.state.operation_lock:
            project = request.app.state.projects.get(parsed_id)
        if project is None:
            return _error_response(404, "not_found", "Not found.")
        return _serialize_project(project)

    @application.put("/api/v1/projects/{project_id}", response_model=None)
    async def update_project(
        request: Request, project_id: str
    ) -> JSONResponse | dict[str, str | None]:
        """Validate and atomically replace a project's editable fields."""
        parsed_id = _parse_task_id(project_id)
        if parsed_id is None:
            return _error_response(
                422,
                "invalid_request",
                "Request validation failed.",
                [{"field": "project_id", "message": "Must be a UUID."}],
            )
        body, body_error = await _read_json_body(request)
        if body_error is not None:
            return body_error
        try:
            payload = ProjectUpdateRequest.model_validate(body)
        except ValidationError as error:
            return _validation_error_response(error)
        with request.app.state.operation_lock:
            try:
                project = request.app.state.projects.update(
                    parsed_id,
                    payload.name,
                    payload.description,
                    payload.icon,
                    payload.color,
                )
            except KeyError:
                return _error_response(404, "not_found", "Not found.")
        return _serialize_project(project)

    @application.delete("/api/v1/projects/{project_id}", response_model=None)
    async def delete_project(
        request: Request, project_id: str
    ) -> JSONResponse | dict[str, bool]:
        """Atomically delete a project and every task assigned to it."""
        parsed_id = _parse_task_id(project_id)
        if parsed_id is None:
            return _error_response(
                422,
                "invalid_request",
                "Request validation failed.",
                [{"field": "project_id", "message": "Must be a UUID."}],
            )
        with request.app.state.operation_lock:
            try:
                request.app.state.projects.delete(parsed_id)
            except KeyError:
                return _error_response(404, "not_found", "Not found.")
        return {"deleted": True}

    @application.get("/api/v1/inbox")
    async def list_inbox(
        request: Request,
    ) -> dict[str, list[dict[str, str | int | bool | None]]]:
        """Return the current saved inbox using the authoritative operation."""
        with request.app.state.operation_lock:
            tasks = request.app.state.tasks.list_inbox()
        return {"items": [_serialize_inbox_task(task) for task in tasks]}

    @application.get("/api/v1/tasks/{task_id}", response_model=None)
    async def get_task(
        request: Request, task_id: str
    ) -> JSONResponse | dict[str, str | int | bool | None]:
        """Return fresh saved detail for a valid task UUID."""
        parsed_id = _parse_task_id(task_id)
        if parsed_id is None:
            return _error_response(
                422,
                "invalid_request",
                "Request validation failed.",
                [{"field": "task_id", "message": "Must be a UUID."}],
            )
        with request.app.state.operation_lock:
            try:
                task = request.app.state.tasks.get(parsed_id)
            except KeyError:
                return _error_response(404, "not_found", "Not found.")
        return _serialize_task_detail(task)

    @application.get("/api/v1/heap")
    async def list_on_heap(
        request: Request,
    ) -> dict[str, list[dict[str, str | int | bool | None]]]:
        """Return all snapshots on the heap in oldest-first order."""
        with request.app.state.operation_lock:
            tasks = request.app.state.tasks.list_on_heap()
        return {"items": [_serialize_task_detail(task) for task in tasks]}

    @application.put("/api/v1/tasks/{task_id}/organization", response_model=None)
    async def organize_task(
        request: Request, task_id: str
    ) -> JSONResponse | dict[str, str | int | bool | None]:
        """Validate and atomically replace the task's organization fields."""
        parsed_id = _parse_task_id(task_id)
        if parsed_id is None:
            return _error_response(
                422,
                "invalid_request",
                "Request validation failed.",
                [{"field": "task_id", "message": "Must be a UUID."}],
            )
        body, body_error = await _read_json_body(request)
        if body_error is not None:
            return body_error
        try:
            payload = OrganizationRequest.model_validate(body)
        except ValidationError as error:
            return _validation_error_response(error)

        with request.app.state.operation_lock:
            try:
                current = request.app.state.tasks.get(parsed_id)
            except KeyError:
                return _error_response(404, "not_found", "Not found.")
            if current.status is TaskStatus.COMPLETED:
                return _error_response(
                    409, "task_completed", "Completed tasks cannot be organized."
                )
            if _format_timestamp(current.updated_at) != payload.expected_updated_at:
                return _error_response(
                    409, "task_conflict", "Task changed since it was loaded."
                )
            try:
                task = request.app.state.tasks.organize_task(
                    parsed_id,
                    title=payload.title,
                    priority=(
                        Priority(payload.priority)
                        if payload.priority is not None
                        else None
                    ),
                    duration=Duration(payload.duration_minutes),
                    externally_blocked=payload.externally_blocked,
                    project_id=(
                        UUID(payload.project_id)
                        if payload.project_id is not None
                        else None
                    ),
                )
            except KeyError:
                return _error_response(404, "not_found", "Not found.")
        return _serialize_task_detail(task)

    @application.post("/api/v1/tasks", status_code=201, response_model=None)
    async def capture(request: Request) -> JSONResponse | dict[str, str]:
        """Validate, save, and return a task title-only inbox snapshot."""
        body, body_error = await _read_json_body(request)
        if body_error is not None:
            return body_error
        try:
            payload = CaptureRequest.model_validate(body)
        except ValidationError as error:
            return _validation_error_response(error)
        with request.app.state.operation_lock:
            task = request.app.state.tasks.capture(payload.title)
        return _serialize_task(task)

    return CORSMiddleware(
        application,
        allow_origins=origins,
        allow_credentials=False,
        allow_methods=["DELETE", "GET", "POST", "PUT"],
        allow_headers=["Content-Type"],
    )


app = create_app()
