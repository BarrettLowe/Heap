# Backend setup

The backend exposes a private HTTP API backed by the existing SQLite task store. It supports health, task capture, Inbox and On-deck lists, task detail, and atomic organization edits.

## Run with Compose

Docker Compose publishes the service on `127.0.0.1:8000` by default:

```sh
docker compose up --build -d
docker compose ps
curl http://127.0.0.1:8000/healthz
```

The SQLite file is `/data/heap.sqlite` in the container and lives in the named `heap-data` volume. Stopping or recreating the container keeps the volume and saved tasks. **`docker compose down -v` deletes the volume and its data.** Do not use `-v` unless you intend to permanently remove the database. Back up the volume before doing maintenance that could remove it.

The API routes are `GET /healthz`, `GET /api/v1/inbox`, `GET /api/v1/on-deck`, `GET /api/v1/tasks/{task_id}`, `POST /api/v1/tasks`, and `PUT /api/v1/tasks/{task_id}/organization`. Capture accepts JSON such as `{"title":"Repair the fence"}`. Organization requires title, priority, duration, the manual `externally_blocked` waiting flag, and the saved `expected_updated_at` comparison token. All 4 editable fields are saved together; use `null` to clear priority or duration. Unfinished tasks with priority and a known duration automatically belong On-deck, including tasks awaiting external dependencies. Incomplete tasks belong in Inbox. There is no move action; supplying the obsolete `move_to_on_deck` field returns `422`. Stale edits and completed-task edits return `409`; invalid request fields return `422`. There is no authentication; do not expose this service to an untrusted network.

## Configuration

- `HEAP_DATABASE_PATH` selects the SQLite file. Compose sets it to `/data/heap.sqlite`; mount durable storage at `/data` when running outside Compose.
- `HEAP_BIND_ADDRESS` selects the host address Compose publishes. The default is `127.0.0.1`, which is private to the host. Set it to a reachable private/VPN interface address only when remote clients need access; avoid `0.0.0.0` and public interfaces.
- `HEAP_PORT` selects the host port; the container listens on port `8000`.
- `HEAP_CORS_ORIGINS` is a JSON list of exact web origins, for example `HEAP_CORS_ORIGINS='["https://heap.example"]'`. The default is `[]`. Do not use wildcard origins. Browser CORS permits GET, POST, and PUT plus Content-Type requests; native Android requests do not use browser CORS.

For local Android emulator access, use `http://10.0.2.2:8000`; a physical device needs an address it can reach, such as the server's Tailscale IPv4 address. For remote Tailscale access, bind Compose to the server's Tailscale interface address (for example, set `HEAP_BIND_ADDRESS` to that interface's `100.x.y.z` address) and confirm VPN/firewall routing allows the client. Do not publish to all interfaces just to make VPN access work.

## Web and transport security

Browsers can call the API only from an origin listed in `HEAP_CORS_ORIGINS`. Include the scheme and port when present, with no path, query, or fragment. CORS is not authentication or network isolation. Serve release web clients over HTTPS and terminate HTTPS in a trusted reverse proxy or VPN layer outside this container; an HTTPS page cannot call an HTTP API because browsers block mixed content. Configure the API's exact HTTPS page origin in the CORS list. Android debug builds may use HTTP for local/VPN development; release builds should use HTTPS and must not enable broad cleartext traffic.

## Placement and time on-deck

Inbox bulk responses include required priority, duration, and waiting metadata; task detail and On-deck responses also include `on_deck_since`. Capture responses retain their original 5 fields. Ordinary qualifying edits preserve time on-deck; clearing a requirement clears its age, and restoring requirements starts a new age. Waiting does not change placement or age. Ranking is not implemented.

Before startup becomes healthy, the operator normalizes legacy qualifying Inbox tasks in 1 atomic batch. Their age and update token start at the actual normalization time, not an inferred historical time. Existing On-deck, completed, and incomplete Inbox tasks and all unrelated data are retained. Repeated startup is a no-op; failure rolls back the batch and aborts startup. GET handlers do not normalize or save.

## SQLite write boundary

Run exactly 1 Uvicorn worker, process, and replica against a given database. The application opens SQLite on its event-loop thread and serializes complete task operations there. Do not run another Heap process or container that writes the same SQLite file: SQLite and this in-process lock do not coordinate multiple application processes. This is a small single-writer setup, not a multi-instance deployment.
