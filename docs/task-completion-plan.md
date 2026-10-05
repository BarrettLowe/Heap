# Heap row completion

Barrett approved a left circular check control on Heap rows. Completion saves immediately, then the row turns readable grey and remains in place. Undo restores its saved fields and original Heap age. Any successful Heap list reload replaces the list and removes completed rows; failed reloads retain them. No Inbox completion or history screen is added.

## Ownership

- Designer: `docs/task-completion-design.md`.
- Backend: Python logic, HTTP endpoint, and Python tests.
- Frontend: Flutter transport, controller, rows, and Flutter tests.
- Coordinator: shared documents, independent review, and verification.

## HTTP addition

`PUT /api/v1/tasks/{task_id}/completion`

```json
{"completed": true, "expected_updated_at": "2026-10-05T00:00:00.000000Z"}
```

Both fields are required; extra fields are rejected. Set `completed` to false to undo. Return the existing task detail using current `on_heap` and `on_heap_since` names. Check the token and persist inside the existing serialized operation boundary. Missing tasks return 404, stale tokens return 409 `task_conflict`, and ineligible transitions return 409 `task_not_on_heap`. Current-state repeats are no-ops. Completion retains unrelated fields and age; undo clears the completion timestamp, preserves age, and advances the comparison token rather than rewinding it.

## Verification

Check confirmed completion, in-place undo, any successful reload, failed reload retention, stale reads, refresh during undo, uncertain writes, strict API validation, persistence, keyboard/screen-reader action semantics, and neutral styling. Actual phone/emulator checks remain pending unless performed.

A timeout does not cancel a server write. A recovery GET that does not match the requested state must retain uncertainty and keep new writes disabled; a successful GET alone is not proof that an earlier write failed.
