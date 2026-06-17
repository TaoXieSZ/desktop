# AhaKey Web Studio

This web surface edits AhaKey profiles through the local `ahakeyd` daemon on
`127.0.0.1:17342`. The daemon validates profile JSON, enforces local
Host/Origin/token checks for state-changing requests, returns dry-run command
plans, and can write shortcut mappings to the connected AhaKey device through
`AhaKeyWebBridgeHelper`.

## Run

```sh
cd ../platforms/macos
swift build
.build/debug/ahakeyd \
  --serve \
  --port 17342 \
  --token dev-token \
  --profile-root "$HOME/Library/Application Support/AhaKey/profiles"

cd ../../web
VITE_AHAKEYD_TOKEN=dev-token \
VITE_AHAKEY_DAEMON_URL=http://127.0.0.1:17342 \
npm run dev -- --host 127.0.0.1 --port 5174
```

The editor stores the daemon token in local browser storage and sends it as
`X-AhaKey-Token` for profile saves and dry-run apply requests.

## Daemon endpoints

- `GET /health` returns daemon liveness and schema version.
- `GET /api/status` returns device, Fn relay, terminal approval relay, profile,
  and blocker state.
- `GET /api/permissions` reports Accessibility, Input Monitoring, and post
  event readiness.
- `GET /api/profiles` lists saved profiles.
- `GET /api/profiles/:id` reads one saved profile.
- `PUT /api/profiles/:id` validates and saves a profile.
- `POST /api/apply` accepts `{ "dryRun": true|false, "profile": { ... } }`.
  Dry-run returns the command plan with `"hardwareMutated": false`; hardware
  apply writes shortcut actions through `AhaKeyWebBridgeHelper`.

## Tested Mode 0 workflow

- Key 1: Right Command (`0xE7`) for Doubao binding.
- Key 2: F19 trigger. `ahakeyd` swallows it and injects terminal approval:
  single press = `Enter`; double press within 280 ms = `Down, Enter`
  for bypass / allow all.
- Key 3: F20 trigger. `ahakeyd` swallows it and injects `Down, Down, Enter`
  for deny / no.
- Key 4: Enter (`0x28`).

The terminal approval relay requires macOS Accessibility, Input Monitoring, and
post-event permission for the daemon process. Check `approvalRelay` in
`GET /api/status` before testing approval keys.

## Shortcut capture

In the profile editor, a Shortcut binding can be set two ways:

- **预设快速选择** — the preset dropdown (Enter / Escape / Tab / … / F20).
- **录入 (capture)** — click 录入, then press the physical key you want to bind,
  optionally holding `⌘` / `⌃` / `⌥` / `⇧`. The press is recorded as USB HID
  usage codes into `action.hidCodes` (modifiers first, then the key), previewed
  as e.g. `⌘ + S · 0xe3 0x16`. `Esc` or clicking elsewhere cancels.

`KeyboardEvent.code` (physical position) drives the mapping in `src/hidKeymap.ts`,
so it is layout-independent. Codes are validated to `0…255` with at most
`98` per binding (the firmware limit, mirroring `AhaKeyProfileValidator`).

Caveats:
- OS-level combos (`⌘Q`, `⌘Tab`, `⌘Space`) never reach the page and cannot be captured.
- **Combo firmware semantics are unverified**: whether the device replays a
  multi-byte `hidCodes` array as a simultaneous chord or a sequence must be
  confirmed on hardware (dry-run `POST /api/apply` to inspect the command plan,
  then write and observe). Single-key capture is unambiguous.

## Verification

```sh
cd web && npm run build
cd ../platforms/macos && swift build
```

## Legacy bridge

`npm run bridge` still starts the older bridge on `127.0.0.1:17341` for the
shortcut helper path. It is dry-run only; hardware-mutating web flows must go
through `ahakeyd`.

```sh
npm run bridge
npm run dev
```

Its `POST /api/remap/shortcut` endpoint accepts
`{ "mode": 0, "keyIndex": 1, "hidCodes": [40], "label": "Enter", "dryRun": true }`.
