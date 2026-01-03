# downloads (packages/downloads)

Reliable download + install primitives for large model assets.

## Responsibilities

- **Atomic downloads**: prevent partially-downloaded assets from being treated as installed.
- **Resume support**: uses HTTP Range requests when possible.
- **Archive extraction**: supports `.tar.gz`, `.tgz`, `.zip`.
- **State streaming**: `watchState(key)` emits `DownloadState` updates for UI.

## Key components

- `AtomicAssetManager`
  - Downloads to a temp file
  - Extracts into a temp directory
  - Atomically renames into the final install dir
  - Writes a `.manifest` file as the install marker
- `AssetSpec`
  - Declares `key`, `downloadUrl`, expected size, optional checksum
- `voices_manifest.json`
  - Declarative list of core assets and voice definitions

## Redirect handling

Hugging Face URLs frequently return redirects; the downloader follows common HTTP redirect codes and then continues.

## Best practices / gotchas

- Always treat the install directory as the unit of atomicity.
- Use checksums when possible (many entries currently use placeholders).
- Keep keys stable: they become on-disk folder names and migration boundaries.
