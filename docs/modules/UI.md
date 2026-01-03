# UI layer (lib/ui)

Material UI screens and reusable widgets.

## Navigation

GoRouter routes are defined in `lib/main.dart`:

- `/` → `LibraryScreen`
- `/book/:id` → `BookDetailsScreen`
- `/playback/:bookId` → `PlaybackScreen`
- `/settings` → `SettingsScreen`

## Key components

- `lib/ui/screens/library_screen.dart` — main library view + entrypoint for import.
- `lib/ui/screens/book_details_screen.dart` — chapter list/metadata.
- `lib/ui/screens/playback_screen.dart` — reading/playback UI.
- `lib/ui/screens/settings_screen.dart` — settings + downloads.
- `lib/ui/widgets/voice_download_manager.dart` — download UI for Kokoro/Piper/Supertonic.

## State management

UI reads state with `ref.watch(...)` and triggers actions via `.notifier`.

Best practice reminders:

- Keep screens mostly declarative; push I/O to providers/services.
- Handle `AsyncValue` explicitly (`loading`, `error`, `data`).
- Avoid passing heavyweight services through widget constructors; prefer providers.
