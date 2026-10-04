#!/usr/bin/env bash
set -euo pipefail

image="${1:-heap:ci}"
container="heap-ci-$$"
volume="${container}-data"

cleanup() {
  docker rm -f "$container" >/dev/null 2>&1 || true
  docker volume rm "$volume" >/dev/null 2>&1 || true
}
trap cleanup EXIT

start_container() {
  docker run --detach --name "$container" --volume "$volume:/data" "$image"
  for attempt in {1..30}; do
    if docker exec "$container" python -c \
      'import json; from urllib.request import urlopen; assert json.load(urlopen("http://127.0.0.1:8000/healthz", timeout=2)) == {"status": "ok"}' \
      >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  docker logs "$container"
  return 1
}

start_container
task_id="$(docker exec -i "$container" python - <<'PY'
import json
from urllib.request import Request, urlopen

base = "http://127.0.0.1:8000"
with urlopen(f"{base}/api/v1/inbox", timeout=5) as response:
    assert json.load(response) == {"items": []}
request = Request(
    f"{base}/api/v1/tasks",
    data=json.dumps({"title": "CI persistence smoke test"}).encode(),
    headers={"Content-Type": "application/json"},
    method="POST",
)
with urlopen(request, timeout=5) as response:
    assert response.status == 201
    task = json.load(response)
    assert task["title"] == "CI persistence smoke test"
    print(task["id"])
PY
)"

# Replace the container while retaining its named SQLite volume.
docker rm -f "$container"
start_container
docker exec -i --env "HEAP_SMOKE_TASK_ID=$task_id" "$container" python - <<'PY'
import json
import os
from urllib.request import urlopen

with urlopen("http://127.0.0.1:8000/api/v1/inbox", timeout=5) as response:
    tasks = json.load(response)["items"]
assert len(tasks) == 1, tasks
assert tasks[0]["id"] == os.environ["HEAP_SMOKE_TASK_ID"], tasks
assert tasks[0]["title"] == "CI persistence smoke test", tasks
print("Container health, capture, and volume persistence verified.")
PY
