# Heap UI

The Flutter Inbox and On the heap task lists talk to the Heap API. Use the real list selector inside Tasks, or tap the central Capture plus to add a title. Tap a task to load fresh detail and edit title, priority, duration, and the manual awaiting flag. Today, Projects, and Settings are visibly unavailable Soon placeholders, not fake pages. There is no fake task data, offline queue, or disk draft cache.

## Configure the API

Pass the server **origin** (scheme, host, and optional port only):

```sh
cd ui
flutter run --dart-define=HEAP_API_BASE_URL=http://10.0.2.2:8000
```

The Android emulator reaches the host machine through `10.0.2.2`. A physical device must use a server address it can reach, such as the host's VPN/Tailscale address. The API must be reachable from that device.

If the value is missing or is not a valid HTTP(S) origin, the app shows a setup message instead of an empty inbox. Android debug builds permit plain HTTP for local development. Release builds do not enable cleartext traffic; use HTTPS. A web app loaded over HTTPS also needs an HTTPS API, because browsers block mixed-content HTTP requests.

For browser access, configure the backend's `HEAP_CORS_ORIGINS` with the exact origin serving the web app (for example `http://localhost:7357`). Do not use a wildcard. The UI does not configure backend CORS.

## Run and verify

```sh
flutter pub get
flutter analyze
flutter test
flutter build apk --debug --dart-define=HEAP_API_BASE_URL=http://10.0.2.2:18081
flutter build apk --release --dart-define=HEAP_API_BASE_URL=https://api.example.test
flutter build web --dart-define=HEAP_API_BASE_URL=https://api.example.test

# Local browser preview; allow http://localhost:8181 in backend CORS.
flutter run -d web-server --web-hostname localhost --web-port 8181 \
  --dart-define=HEAP_API_BASE_URL=http://127.0.0.1:18081
```

The origins above are examples: `18081` is the current isolated integration backend; normal Compose defaults to `8000`. The HTTPS origin is a compile-only placeholder, not a deployment. Existing example Android app identity and signing remain unchanged.

## Heap filters

The Heap page has Time and Priority pickers; only 1 can be active. Time is a minimum duration (`≥30m` includes 30/60/120/240 minutes), while Priority matches exactly. Selecting either clears the other; opening or cancelling a picker keeps the selection. `Any` or `Clear filter` shows the full heap again. Inbox is unfiltered. Filters preserve incoming server order and waiting tasks, use the already-fetched list without extra HTTP requests, and survive editing, refresh, and list navigation until app restart. A saved task excluded by the filter stays saved; feedback explains why its row is hidden. Project filtering is deferred.

## Organization and recovery

Capture is title-only and starts in Inbox. One `Save` submits title, nullable priority, nullable duration, and the required awaiting boolean atomically, including a valid unchanged save. Priority plus known duration qualifies unfinished tasks to be on the heap automatically. Clearing a requirement returns a task to Inbox; restoring requirements puts it on the heap on Save. The manual `Awaiting external dependencies` checkbox does not affect membership or ordering: waiting tasks remain in their actual list with a badge. Tasks on the heap are ordered by server-supplied age, not priority, and being on the heap does not imply unblocked or started. There is no manual move action or hidden-task feature.

All requests have a 10-second timeout through response-body completion. Only server-confirmed results move rows or clear a successful capture draft. Failed refreshes keep previously loaded rows explicitly stale and do not turn a confirmed save into a failed write.

Uncertain capture retains its draft and warns about duplicates. Refresh before a deliberately warned resubmission; matching a title is not proof of capture success. Uncertain organization saves instead use `Reload saved task` on the existing ID, never capture or automatic PUT retries. Matching all 4 fields and automatically derived status confirms the current saved state, independently of waiting. Differing or unchanged detail requires an explicit `Use saved version` or `Keep my edits` choice; the earlier write might still finish. Use saved version adopts all fetched editable values. Keep my edits retains all 4 displayed draft values, including awaiting, and adopts the fresh comparison token/status; a deliberate Save replaces all 4 server fields. Neither choice writes automatically.

Idle capture Close retains text, and reopen restores it. Pending POST blocks dismissal and duplicate submission but permits newer text; confirmation clears/closes only an unchanged submitted draft. Uncertain capture state survives close/reopen with a list warning. Dirty editor back/cancel asks before discarding. Leaving an uncertain editor warns that discarding local text cannot undo a possible server save. Inputs and editor navigation are blocked during PUT. Background list refreshes do not restore old focus over newer typing/navigation. Drafts and list positions survive normal in-app navigation only; browser reload/tab close does not preserve unsaved text.

The additive transport uses `GET /api/v1/tasks/{id}`, `GET /api/v1/heap`, and `PUT /api/v1/tasks/{id}/organization`. Nullable fields and the required `externally_blocked` boolean are sent explicitly; the obsolete move key is never sent. Bulk Inbox metadata is required and validated, not guessed from capture defaults or fetched per row. The exact 6-digit UTC `updated_at` token is echoed from fresh detail. Backend CORS must permit PUT as described in `../docs/api-contract.md`.
