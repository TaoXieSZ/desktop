# Contributing

Thanks for helping improve AhaKey Studio.

## Start Here

1. Read [DEVELOPMENT.md](./DEVELOPMENT.md) for local setup.
2. Read [ARCHITECTURE.md](./ARCHITECTURE.md) and [docs/module-map.md](./docs/module-map.md) before moving code.
3. Keep pull requests focused. Small PRs are easier to review.
4. Run:

```sh
swift build
swift test
```

## Where Changes Belong

- App shell and window composition: `Sources/Views/App`
- AhaKey Studio UI: `Sources/Views/Studio`
- Workbench prototype UI: `Sources/Views/Workbench`
- BLE protocol and transport: `Sources/BLE`
- Pure Studio sync/planning logic: `Sources/Utilities/Studio` and `Sources/Utilities/OLED`
- VoiceAgent core runtime: `Sources/VoiceAgent`
- Tests: `Tests/AhaKeyConfigTests`

## Testing Expectations

Prefer tests that do not require real hardware. Good test targets include:

- BLE frame encoding and response parsing
- Studio draft migration and dirty-state logic
- OLED placement planning
- VoiceAgent core message/tool behavior

Hardware-dependent behavior should be isolated behind small interfaces where possible and documented in the PR.

## Pull Request Expectations

Every PR should include:

- A clear summary of user-visible behavior or refactoring scope
- Test commands run locally
- Screenshots for visible UI changes
- Notes about hardware requirements, if any

Do not include API keys, signing identities, local paths, or private app credentials in issues, logs, or commits.
