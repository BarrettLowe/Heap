# Heap HTTP contract

**Approved revision:** automatic organization, manual external waiting, and retained time-on-deck tracking. Barrett approved implementation after planning. This replaces the prior explicit-move contract. No ranking engine or hidden-task feature is added.

Python owns rules and durable storage. Flutter is server-backed: no disk task cache, queued writes, automatic write retries, or offline synchronization. Contract changes remain coordinator-owned.

## Routes

Use these exact paths without trailing slashes. JSON uses UTF-8. There are no credentials or idempotency keys in this slice.

| Method and path | Request | Success |
| --- | --- | --- |
| `GET /healthz` | None | `200 {"status":"ok"}` after initialization and normalization |
| `POST /api/v1/tasks` | `{"title":"Fix driveway washout"}` | `201 CaptureTask`, after persistence |
| `GET /api/v1/inbox` | None | `200 {"items":[InboxTask,...]}` |
| `GET /api/v1/tasks/{task_id}` | None | `200 TaskDetail` |
| `GET /api/v1/on-deck` | None | `200 {"items":[TaskDetail,...]}` |
| `PUT /api/v1/tasks/{task_id}/organization` | Full editor fields and comparison token | `200 TaskDetail`, after persistence or confirmed no-op |

IDs are lowercase canonical hyphenated UUID strings. Invalid path UUIDs produce `422 invalid_request`; missing tasks produce `404 not_found`. Dates use exact UTC `YYYY-MM-DDTHH:MM:SS.ffffffZ`, including zero microseconds. Preserve the comparison token exactly; it is not an operation time.

## Capture and Inbox

Capture remains title-only. Require a strict string, trim surrounding whitespace, reject blank/invalid-Unicode titles and extra fields. Do not impose an invented length limit. Clients never supply IDs or timestamps.

`CaptureTask` retains the original 5-field response:

```json
{
  "id": "d4be2fc9-49b7-46a6-9981-1f063eed03ea",
  "title": "Fix driveway washout",
  "status": "inbox",
  "created_at": "2026-10-03T12:34:56.123456Z",
  "updated_at": "2026-10-03T12:34:56.123456Z"
}
```

Creation guarantees unset priority, unknown duration, and `externally_blocked=false`. Creation timestamps are equal. These defaults apply to confirmed title-only creation, not arbitrary missing list metadata.

`InboxTask` returned by the bulk GET adds 3 required fields to the original 5:

```json
{
  "id": "d4be2fc9-49b7-46a6-9981-1f063eed03ea",
  "title": "Fix driveway washout",
  "status": "inbox",
  "created_at": "2026-10-03T12:34:56.123456Z",
  "updated_at": "2026-10-03T12:34:56.123456Z",
  "priority": 2,
  "duration_minutes": null,
  "externally_blocked": true
}
```

Inbox contains unfinished tasks missing priority or known duration. Order remains ascending creation time, then ID. Empty lists are `{"items":[]}`. No pagination. Older clients may ignore additive metadata; new bulk-list rendering must validate its presence/types rather than guess or GET each row separately. Preserve original capture tests/behavior; update list fixtures where the additive response requires it.

## Detail and On-deck

`TaskDetail` has these 9 fields:

```json
{
  "id": "d4be2fc9-49b7-46a6-9981-1f063eed03ea",
  "title": "Fix driveway washout",
  "status": "on_deck",
  "created_at": "2026-10-03T12:34:56.123456Z",
  "updated_at": "2026-10-04T09:00:00.123456Z",
  "priority": 2,
  "duration_minutes": 30,
  "on_deck_since": "2026-10-04T09:00:00.123456Z",
  "externally_blocked": true
}
```

- Status: `inbox`, `on_deck`, or `completed`. Completed detail is readable; organization writes are rejected.
- Priority: null or strict integer 1–5. Labels: P1 Critical, P2 Important, P3 Normal, P4 Someday, P5 Maybe. P1 is highest.
- Duration: null (Unknown) or strict integer minutes 5/15/30/60/120/240.
- Waiting: required strict boolean `externally_blocked`, manually edited only. No hiding field, reason text, or automatic updates.
- `on_deck_since`: canonical UTC or null; On-deck requires a timestamp. Completed tasks may retain an earlier timestamp.

On-deck membership is qualifying unfinished work: priority assigned and duration known. It is not a separate manual flag/action. Both waiting and prerequisite-blocked tasks remain in this organized pool, with waiting clearly marked. This is not an actionable-only recommendation view or ranking. List order remains ascending `on_deck_since`, then ID. Queries should express qualification rather than rely on an independently editable membership choice; persisted lifecycle snapshots may remain an internal representation maintained by operations. Inbox and On-deck must partition unfinished tasks consistently.

## One atomic organization Save

PUT requires all 5 fields:

```json
{
  "title": "Fix driveway washout",
  "priority": 2,
  "duration_minutes": 30,
  "externally_blocked": true,
  "expected_updated_at": "2026-10-03T12:34:56.123456Z"
}
```

Missing priority/duration is invalid; explicit null clears them. Waiting is required, never nullable/default-false. Load it from fresh detail and submit the draft value. Reject booleans/floats/numeric strings for integers, unsupported enum values, malformed tokens, invalid titles, and extra fields. **`move_to_on_deck` is removed; any supplied value, including false, is an extra field and produces 422.** Missing organization requirements are valid saves to Inbox, not validation failures.

Check fresh missing/completed/stale state and apply the complete operation inside the existing serialized boundary:

- Missing: `404 not_found`.
- Completed: `409 task_completed`, including unchanged requests.
- Saved token differs: `409 task_conflict` without edits.
- Invalid body: `422 invalid_request` without edits.
- Unchanged final snapshot: return it without saving or reading time.
- Meaningful change: read UTC once; replace title/priority/duration/waiting and derived organization together; save once. Failed saves cannot partially persist.

Final organization follows these rules:

| Unfinished final snapshot | Placement / age |
| --- | --- |
| Priority assigned and duration known | On-deck automatically |
| Either requirement missing | Inbox; `on_deck_since=null` |
| Still On-deck after ordinary edits | Preserve exact age |
| Entering/re-entering On-deck | New age from actual operation time |
| Waiting checked/cleared alone | No independent effect on membership, age, priority, or ordering |

Preserve IDs, creation time, project, completion data, dependency links, and every unrelated field. Existing snapshot-edit operations must apply the same organization policy; completed tasks never resurrect. Legacy Python `move_to_on_deck` may remain an idempotent compatibility operation, but no HTTP/UI uses it.

### Existing data and startup

Before publishing a healthy app, explicitly normalize existing qualifying Inbox snapshots through the operator. Select qualifying tasks in Python, retain unrelated fields/manual flags, read UTC once only if changes exist, and persist all normalized snapshots in 1 atomic batch. Actual normalization time supplies their new age/update token; never invent historical ages. Existing On-deck/completed/incomplete Inbox snapshots remain untouched. Failure aborts startup and rolls back the batch. No schema field or migration marker is needed; repeated normalization is a no-op. GET/list handlers remain read-only.

## Errors

```json
{"error":{"code":"invalid_request","message":"Request validation failed.","fields":[{"field":"title","message":"Must not be blank."}]}}
```

`fields` is always a list; non-field errors use `[]`. Use status/code, not message matching. Do not expose raw request bodies, traceback, or database details.

| Status | Code | Meaning |
| --- | --- | --- |
| 422 | `invalid_request` | Invalid JSON/path/body; no write |
| 415 | `unsupported_media_type` | Non-JSON write; no write |
| 404 | `not_found` | Missing task/path |
| 405 | `method_not_allowed` | Unsupported method; retain Allow header |
| 409 | `task_completed` / `task_conflict` | Terminal/stale organization attempt |
| 500 | `internal_error` | Generic unexpected failure; write outcome may be uncertain |

## Client recovery and confirmed updates

- GET fresh known-ID detail before editing; separate saved snapshot, draft, submitted draft, and fetched comparison.
- One Save; valid unchanged saves allowed. Checkbox changes only the draft. Dirty back/cancel offers Keep editing/Discard changes. Disable submission, fields, and route departure during PUT.
- Preserve drafts on rejection, conflict, unavailability, and uncertain saves. Missing/completed snapshots are read-only.
- Confirmed Save updates/removes/upserts the known ID in both lists, invalidates obsolete reads, and navigates to the returned status before refreshing both lists. Refresh failure remains a successful Save, with persistent `Saved, but lists could not be refreshed.` and stale labeling.
- Delayed refresh must never steal focus from a newer capture interaction or navigation. Keep scroll positions and accessible focus without replaying stale restoration.
- Timeout, lost response, malformed/wrong-ID success, or 5xx means PUT may have succeeded. No automatic retry or POST duplication. Recovery GET uses the same known ID.
- Match trimmed submitted title, nullable priority/duration, waiting boolean, and automatic intended status (qualification independent of waiting). A match confirms current state, not request attribution.
- Differing/unchanged GET retains uncertainty: the earlier write may still finish. Explicit Use saved version adopts all fetched values; Keep my edits keeps the displayed draft's 4 fields and adopts the fetched token/status. Clearly explain that a later deliberate Save replaces all 4 server fields, including waiting. Neither choice writes automatically.
- Failed reconciliation retains draft/warning; missing/completed outcomes remain read-only. Leaving uncertain edits warns that discarding text cannot undo a possible saved write. No disk draft cache.

Capture keeps its original safeguards: preserve newer input, block duplicate pending POST, clear only confirmed submitted text, refresh before deliberate uncertain resubmission with a duplicate warning. Title matches never confirm capture. GET refresh/retry never repeats a write. A failed refresh cannot turn confirmed capture into failure.

## Transport and deployment

- Configure `HEAP_API_BASE_URL` with an HTTP(S) origin only: no credentials/query/fragment/non-root path. Invalid setup is visible, not fake empty data.
- 10-second timeout through full response-body completion; no automatic writes/retries.
- Android debug may use development HTTP; release has INTERNET permission without broad cleartext opt-in and needs HTTPS. Emulator host API is `http://10.0.2.2:18081` for this preview; physical phones require a reachable VPN/server address. HTTPS web pages require HTTPS APIs.
- FastAPI/Uvicorn; 1 worker/process/replica, complete-operation serialization. Open/use/close SQLite on its owning event-loop thread, not shared sync threadpool routes. Other writers must not use the same DB concurrently. Token protection is not a general multiprocess revision guarantee.
- `HEAP_DATABASE_PATH`; Compose persists `/data/heap.sqlite` in `heap-data`. Preserve volumes: `docker compose down -v` is destructive.
- Container `0.0.0.0:8000`, host defaults private `127.0.0.1:8000`; explicit VPN binding supported. No public exposure/firewall/auth expansion.
- `HEAP_CORS_ORIGINS`: explicit JSON list, no wildcard/credentials. GET/POST/PUT/OPTIONS and Content-Type; CORS on allowed-origin errors.
- Non-root container, locked production dependencies, health check. HTTPS termination/VPN routing remain external. No dependency/deployment/schema changes required by this revision.
