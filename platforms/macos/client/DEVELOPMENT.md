# Development

## Requirements

- macOS 14 or newer
- Xcode with Swift 5.9 or newer
- Swift Package Manager

## Build

```sh
swift build
```

## Test

```sh
swift test
```

The test suite is intended to cover logic that does not require AhaKey hardware. BLE integration and permission flows should be tested manually until those seams are abstracted.

## Run Locally

For day-to-day development:

```sh
swift run AhaKeyConfig
```

For scripted app builds and packaging, use the scripts in `scripts/`.

## Directory Layout

- `Sources/AhaKeyConfigApp.swift`: macOS app entry point
- `Sources/Views`: SwiftUI views grouped by feature
- `Sources/Utilities`: supporting services grouped by responsibility
- `Sources/BLE`: protocol frames, response parsing, and CoreBluetooth manager
- `Sources/Models`: shared app configuration models
- `Sources/VoiceAgent`: reusable VoiceAgent runtime library
- `Sources/Agent`: background agent executable
- `Tests`: SwiftPM XCTest tests

## Local Secrets

Do not commit local API keys, app secrets, provisioning profiles, or signing identities. If a feature needs credentials, document the environment variable or Keychain item it expects.
