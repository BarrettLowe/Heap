# Heap HTTP contract

This is the shared contract for the first server-backed inbox. Python owns behavior and storage. Flutter does not save locally, queue writes, rank tasks, or calculate eligibility. Both agents must coordinate contract changes with the coordinator before implementing them.

## Requests and responses

Use these exact paths without trailing slashes. JSON uses UTF-8. Clients do not supply IDs or timestamps. There are no credentials or idempotency keys in this slice.

| Method and path | Request | Successful response |
| --- | --- | --- |
| `GET /healthz` | No body | `200 {"status":"ok"}` after database initialization |
| `GET /api/v1/inbox` | No body | `200 {"items":[InboxTask, ...]}` |
| `POST /api/v1/tasks` | JSON `{"title":"Fix driveway washout"}` | `201 InboxTask`, only after saving |

An `InboxTask` has exactly these fields:

```json
{
  "id": "d4be2fc9-49b7-46a6-9981-1f063eed03ea",
  "title": "Fix driveway washout",
  "status": "inbox",
  "created_at": "2026-10-03T12:34:56.123456Z",
  "updated_at": "2026-10-03T12:34:56.123456Z"
}
```

- IDs are lowercase canonical hyphenated UUID strings.
- Timestamps are RFC 3339 UTC with a `Z` suffix and 6 fractional digits. Python supplies them; capture timestamps are equal.
- Listing uses the existing oldest-first inbox ordering, with ID tie-breaking. Other statuses do not appear. An empty list is `{"items":[]}`. This slice has no pagination.
- Capture accepts only a strictly string-valued `title`. Trim surrounding whitespace, reject an empty result, and reject extra fields. This is HTTP input validation, not a claim that the existing Python core validates titles. Do not invent a length limit.
- Clients may ignore future additional response fields, but the server returns only the fields specified here for now.

## Errors

Every application API error has this shape:

```json
{
  "error": {
    "code": "invalid_request",
    "message": "Request validation failed.",
    "fields": [
      {"field": "title", "message": "Must not be blank."}
    ]
  }
}
```

`fields` is always a list; non-field errors use `[]`. Clients use status and code rather than matching human-readable messages. API validation errors must not expose raw request bodies. Unexpected failures are logged server-side without returning traceback or database details to the client.

| HTTP status | Code | Meaning |
| --- | --- | --- |
| `422` | `invalid_request` | Malformed JSON, missing/wrong/extra fields, or blank title; no write |
| `415` | `unsupported_media_type` | POST is not JSON; no write |
| `404` | `not_found` | Unknown path |
| `405` | `method_not_allowed` | Unsupported method; preserve the `Allow` header |
| `500` | `internal_error` | Unexpected failure; generic client message |

There are no organization, ranking, recurrence, task-detail, or authentication endpoints yet. This is a private-network skeleton, not a public authenticated deployment.

## Client behavior

- Configure the server origin using `--dart-define=HEAP_API_BASE_URL=...`. Missing or invalid configuration is a visible setup error, not a fake empty inbox. Allow only HTTP(S) origins without credentials, query, fragment, or non-root path.
- Initial loading, server-empty, loaded, and unavailable states must be distinct. Provide GET refresh/retry; do not automatically retry POST.
- Request timeout: 10 seconds through response-body completion, a starting limit to avoid indefinitely hanging requests.
- Keep draft text on failure. Disable repeated capture while a POST is pending. Clear only the successfully submitted draft, without erasing newer text typed during the request.
- Add only server-confirmed captures. Refresh after capture; a refresh failure must not report the already-confirmed capture as failed. Obsolete GET results must not overwrite newer state.
- Previously loaded tasks may remain visible during failure, but label them stale. Do not represent stale data as a current successful load.
- A POST timeout, lost response, malformed success response, or server `5xx` has an unknown outcome: it may already have saved. Display "Capture may have succeeded. Refresh the inbox before submitting again." Never retry automatically; any deliberate resubmission must warn about duplicates. Matching a title does not prove that capture succeeded.
- Android debug builds may use HTTP for local/VPN development. Do not allow broad cleartext in release builds. Add INTERNET permission to the main manifest. Emulator host access uses `http://10.0.2.2:8000`; physical devices need a reachable server/VPN address.
- Keep shared Dart code web-compatible and add a minimal web target. An HTTPS web page needs an HTTPS API to avoid browser mixed-content blocking.

## Backend configuration and access

- FastAPI + Uvicorn; existing `TaskOperator` and SQLite stores remain authoritative. Keep existing logic and persistence files unchanged in this slice.
- Run 1 worker, process, and replica. Serialize complete operator calls. Initialize, use, and close SQLite on its owning thread; do not route a shared SQLite connection through FastAPI's synchronous worker threadpool. Other processes must not write the same database concurrently.
- `HEAP_DATABASE_PATH`: SQLite location; Compose uses `/data/heap.sqlite` in the named `heap-data` volume mounted at `/data`.
- Container listens on `0.0.0.0:8000`. Host publication defaults to `127.0.0.1:8000`; explicit `HEAP_BIND_ADDRESS` may select the server's VPN interface. Do not default to public exposure.
- `HEAP_CORS_ORIGINS`: explicit JSON list of permitted web origins; default `[]`, no wildcard or credentials. Allow GET/POST and Content-Type, with OPTIONS preflight and CORS headers on errors for allowed origins.
- Run as non-root, install locked production dependencies, and include a health check. Document volume retention and the destructive effect of `docker compose down -v`.
- HTTPS termination/VPN routing stays outside this container. Do not silently open firewall rules, add public exposure, or invent credentials.
