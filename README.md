# Heap

Heap is a personal task and project manager with a Python core and an Android-first
Flutter interface. Requirements are in `personal_task_project_manager_v1_spec.md`;
progress is tracked in `TASKS.md`.

## Server-backed app setup

The framework setup connects the Flutter inbox to the existing Python capture and
listing operations. It uses a Docker/Compose backend and keeps web support viable.
It does not implement unfinished ranking or recurrence features.

- [Framework plan and file ownership](docs/framework-plan.md)
- [Shared HTTP contract](docs/api-contract.md)
- [Backend setup](docs/backend.md)
- [Flutter setup](ui/README.md)

The app requires a connection to the server. It does not cache tasks or queue
offline edits. Keep the backend private through VPN/Tailscale; this skeleton does
not add public authentication.

### Local Android quick start

From the repository root:

```sh
docker compose up --build -d --wait
cd ui
flutter run -d emulator-5554 --dart-define=HEAP_API_BASE_URL=http://10.0.2.2:8000
```

Start the emulator first, and use its actual ID if it differs. The database stays
in the Compose volume across container restarts. **`docker compose down -v`
deletes that data.** Physical phones need a reachable VPN server address;
release builds need HTTPS. See the setup links above for web/CORS configuration.

## Run tests

Install [uv](https://docs.astral.sh/uv/), then run:

```sh
uv run pytest
```

uv creates the virtual environment and installs the project and test dependencies.

To check coverage:

```sh
uv run pytest --cov=heap --cov-report=term-missing --cov-fail-under=80
```

## Continuous integration and container images

GitHub Actions runs the Python tests (with an 80% coverage minimum), Flutter
analysis and tests, and a Docker build/smoke test on every pull request. The smoke
test checks API health, task capture, and SQLite persistence after replacing the
container. CI uses Python 3.12, uv 0.9.22, and Flutter 3.47.6; dependencies are
installed from the committed lockfiles.

After all checks pass, pushes to `master` publish the backend container to
`ghcr.io/barrettlowe/heap:latest` and `ghcr.io/barrettlowe/heap:sha-<full-commit-sha>`.
Version tags such as `v0.1.0` also publish a `0.1.0` image tag; they do not move
`latest`. Pull requests never publish images. The workflow can also be run
manually; publishing is enabled only when `master` is selected.

Publishing uses GitHub's built-in `GITHUB_TOKEN`; no registry secret is needed.
See [Backend setup](docs/backend.md#run-a-published-image) for deployment commands.

## First working slice

`TaskOperator.capture(title)` creates an inbox task and explicitly saves it through
`TaskStore`. `SQLiteTaskStore` stores it in SQLite and retrieves independent
`Task` dataclass snapshots. Editing a snapshot does not automatically save it.

`TaskOperator.list_inbox()` returns inbox snapshots oldest-first, with ID as the
tie-breaker for equal creation timestamps. An empty inbox returns `[]`.

The logic layer lives in `src/heap/logic/`, persistence in
`src/heap/persistence/`, and the HTTP interface in `src/heap/interface/`.
The Flutter inbox calls the HTTP interface, which uses these same capture and
listing operations.

Production capture reads current UTC time. Tests replace that time source;
callers do not supply timestamps or configure a clock.

Ranking is not implemented yet. The HTTP interface trims titles and rejects
blank or invalid input; the core capture operation has no title-validation rule.

## Projects

`ProjectOperator.create(name, description=None)` creates and explicitly saves an
active project. `ProjectOperator.get(project_id)` returns a snapshot or `None`
for an unknown ID. `SQLiteProjectStore` persists projects in the same database
file used for tasks.

```python
from pathlib import Path

from heap.logic.project_operator import ProjectOperator
from heap.persistence.sqlite_project_store import SQLiteProjectStore

with SQLiteProjectStore(Path("heap.sqlite")) as store:
    projects = ProjectOperator(store)
    project = projects.create("Repair the fence", "Replace the north fence")
    saved = projects.get(project.id)
```

Project priority and completion behavior are not implemented yet.

## Task priority and duration

Tasks have an optional `Priority` (P1 Critical, P2 Important, P3 Normal,
P4 Someday, P5 Maybe) and a `Duration` bucket: unknown, 5, 15, 30, 60, 120,
or 240 minutes. Priority codes identify importance levels, not ranking weights.
`Priority.label` gives the descriptive label; `Duration.minutes` returns the
estimate, or `None` for unknown.

Title-only capture leaves priority unset and duration unknown. SQLite saves and
retrieves both fields, and adds the columns when opening a database created by
the earlier capture slice.

`TaskOperator.set_priority(task_id, priority)` and
`TaskOperator.set_duration(task_id, duration)` explicitly save edits and return
the updated snapshot. Use `None` to clear priority or `Duration.UNKNOWN` to
clear the estimate. A changed value updates `updated_at`; assigning the same
value leaves the timestamp unchanged and does not save. Missing task IDs raise
`KeyError`. Clearing priority or resetting duration to unknown returns an
on-deck task to the inbox and clears `on_deck_since`.

```python
tasks.set_priority(task.id, Priority.P2)
tasks.set_duration(task.id, Duration.THIRTY_MINUTES)
```

## Task titles and project assignment

`TaskOperator.set_title(task_id, title)` saves a title change.
`TaskOperator.set_project(task_id, project_id)` assigns an existing project;
pass `None` to remove the assignment. Both follow the same timestamp and no-op
rules as priority/duration edits, and neither moves the task on-deck.

Supply a project store to `TaskOperator` when assigning a project. Unknown task
or project IDs raise `KeyError`; assigning a non-null project without a project
store raises `ValueError`. Capture and other edits do not require a project
store. SQLite upgrades older task tables with a nullable `project_id` column.

```python
from heap.logic.task_operator import TaskOperator
from heap.persistence.sqlite_task_store import SQLiteTaskStore

with SQLiteProjectStore(Path("heap.sqlite")) as project_store:
    project = ProjectOperator(project_store).create("Fence repair")
    with SQLiteTaskStore(Path("heap.sqlite")) as task_store:
        tasks = TaskOperator(task_store, project_store)
        task = tasks.capture("Repair the fence")
        task = tasks.set_title(task.id, "Replace the north fence boards")
        task = tasks.set_project(task.id, project.id)
```

## Moving tasks on-deck

`TaskOperator.move_to_on_deck(task_id)` moves an inbox task to `TaskStatus.ON_DECK`.
Priority must be assigned and duration known; a project is optional. The move
saves `on_deck_since` and `updated_at` using the same current UTC timestamp,
without changing `created_at`. The task no longer appears in inbox listings.

Repeated calls on an on-deck task do not save or reset its timestamps. Ordinary
edits preserve `on_deck_since`, which will be used for ranking age and staleness.
Missing task IDs raise `KeyError`; missing priority or duration raises `ValueError`.
On-deck means organized work, not necessarily unblocked or already started.

Clearing priority or resetting duration to unknown returns an on-deck task to
the inbox, clears `on_deck_since`, and updates `updated_at` in the same save.
Restoring the missing value leaves it in the inbox until explicitly moved
on-deck again, which starts a new on-deck timestamp.
