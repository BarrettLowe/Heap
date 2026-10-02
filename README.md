# Heap

A Python core for a personal task and project manager. Requirements are in
`personal_task_project_manager_v1_spec.md`; progress is tracked in `TASKS.md`.

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

## First working slice

`TaskOperator.capture(title)` creates an inbox task and explicitly saves it through
`TaskStore`. `SQLiteTaskStore` stores it in SQLite and retrieves independent
`Task` dataclass snapshots. Editing a snapshot does not automatically save it.

`TaskOperator.list_inbox()` returns inbox snapshots oldest-first, with ID as the
tie-breaker for equal creation timestamps. An empty inbox returns `[]`.

The logic layer lives in `src/heap/logic/`, persistence in
`src/heap/persistence/`. There is no interface layer yet; tests exercise the
same capture operation a future interface will call.

Production capture reads current UTC time. Tests replace that time source;
callers do not supply timestamps or configure a clock.

Ranking and title-validation rules are not implemented yet.

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
