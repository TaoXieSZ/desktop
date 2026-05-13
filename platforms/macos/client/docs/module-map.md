# Module Map

This map helps contributors decide where new code belongs.

## Views

- `Sources/Views/App`: app shell and root workspace switching.
- `Sources/Views/Studio/Core`: main AhaKey Studio composition and state wiring.
- `Sources/Views/Studio/Shell`: top bar, sidebar, status bar, shared Studio chrome.
- `Sources/Views/Studio/Canvas`: keyboard visualization and canvas pane.
- `Sources/Views/Studio/Workspaces`: secondary Studio workspaces and log panels.
- `Sources/Views/Studio/Controls`: reusable Studio editor controls.
- `Sources/Views/Studio/Sheets`: modal sheets and permission/OLED previews.
- `Sources/Views/Workbench`: legacy/prototype workbench screens.
- `Sources/Views/Device`: device information and direct device tools.
- `Sources/Views/Voice`: VoiceAgent UI and voice HUD.
- `Sources/Views/Feishu`: Feishu setup screens.

## Utilities

- `Sources/Utilities/Agent`: launch agent installation, process state, and ownership coordination.
- `Sources/Utilities/Audio`: native macOS speech capture/transcription.
- `Sources/Utilities/OLED`: OLED assets, GIF encoding, and placement planning.
- `Sources/Utilities/Studio`: Studio draft diffing and command generation.
- `Sources/Utilities/System`: local system/debug helpers.
- `Sources/Utilities/Voice`: voice key routing, voice session state, and voice model state.

## Core Runtime

- `Sources/BLE`: protocol frames, response parsing, CoreBluetooth transport, upload queues.
- `Sources/Models`: app configuration models and migrations.
- `Sources/VoiceAgent`: agent runtime, tools, memory, networking, and integrations.
- `Sources/Agent`: background helper executable.

## Tests

- `Tests/AhaKeyConfigTests`: XCTest coverage for non-hardware logic.

Prefer placing new logic in a testable non-view file first, then wiring it into SwiftUI.
