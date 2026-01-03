# App layer (lib/app)

The app layer wires UI to domain + packages via Riverpod providers.

## Responsibilities

- Create and scope core services (paths, download managers, routing engine).
- Expose stable providers consumed by UI and screens.
- Own cross-cutting configuration (settings, theme toggles, etc.).

## Key files

- `lib/main.dart` — app entrypoint + GoRouter routes.
- `lib/app/app_paths.dart` — resolves cache dirs for books, audio cache, and model assets.
- `lib/app/tts_providers.dart` — **TTS download manager** + engine adapter providers + routing engine provider.
- `lib/app/settings_controller.dart` — persistent settings (e.g., dark mode).

## Provider conventions

- Prefer `Provider` for pure, synchronous wiring.
- Prefer `FutureProvider` / `AsyncNotifier` when the provider must perform I/O.

### Example: TTS download state

- `ttsDownloadManagerProvider` exposes an `AsyncValue<TtsDownloadState>`.
- UI widgets should render loading/error states and only interact with `.notifier` when ready.

## Extension points

- Add a new engine:
  1. Add engine type + voice IDs in `core_domain`.
  2. Add adapter + routing in `packages/tts_engines`.
  3. Add download assets / manifest entries and update `lib/app/tts_providers.dart`.
  4. Add platform implementation (Android plugin) if needed.
