# Heap UI

The Flutter inbox talks to the Heap API; it has no fake data or offline queue.

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
flutter build apk --debug --dart-define=HEAP_API_BASE_URL=https://api.example.test
flutter build web --dart-define=HEAP_API_BASE_URL=https://api.example.test
```

The first screen supports inbox loading, retry, empty state, and capture. Capture is confirmed only by the server. If a write times out or returns an uncertain response, refresh before attempting it again to avoid duplicate tasks.
