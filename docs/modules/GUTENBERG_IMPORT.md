# Project Gutenberg (Gutendex) import

_Date: 2026-01-03_

## Goal
Add a “Free books” browsing + one-tap import flow backed by **Project Gutenberg** via the **Gutendex** API, mirroring the UX from the previous app (`/home/william/Projects/audiobook_flutter/`) while fitting the v2 architecture.

Non-goals (for the first iteration): account/login, DRM books, OPDS servers, or multi-format (Kindle/HTML) ingestion.

---

## How the previous app implemented it (full analysis)

### 1) Data source (Gutendex)
The previous app did not scrape gutenberg.org directly; it used **Gutendex** (a public API over Project Gutenberg).

**Endpoints used** (see `lib/src/services/gutendex/gutendex_client.dart` in the old app):
- Top list:
  - `GET https://gutendex.com/books?sort=popular&mime_type=application/epub+zip&copyright=false`
- Search:
  - `GET https://gutendex.com/books?search=<q>&mime_type=application/epub+zip&copyright=false`
- Pagination:
  - Follow `next` / `previous` URLs returned by the API.

### 2) Models / parsing
Old app files:
- `lib/src/services/gutendex/gutendex_models.dart`
- `lib/src/services/gutendex/gutendex_client.dart`

Key choices:
- A minimal model layer: `GutendexPage`, `GutendexBook`, `GutendexPerson`.
- A convenience getter `GutendexBook.epubUrl`:
  - Prefers `application/epub+zip` format.
  - Falls back to keys that start with that MIME type.

### 3) “Browse + Search” state management
Old app files:
- `lib/src/state/free_books_controller.dart`
- UI: `lib/src/screens/free_books_screen.dart`

Implementation details:
- A single `FreeBooksController` (Riverpod `Notifier`) managed:
  - Top list state (`topBooks`, `topNext`, `isTopLoading`, `topError`)
  - Search state (`searchQuery`, `searchResults`, `searchNext`, `isSearchLoading`, `searchError`)
- Search was debounced in the UI (`Timer` ~300ms).
- Stale request protection:
  - `_searchRequestId` / `_topRequestId` counters ensured only the latest network response updates state.
- “Top 100 (popular)” behavior:
  - The controller caps results to 100 and stops fetching more.

### 4) Cover fetching (for list UI)
Old app file:
- `lib/src/services/gutendex/gutendex_image_fetcher.dart`

Behavior:
- Attempts to find an image URL from `formats` (`image/jpeg`, `image/png`, or heuristic “cover/jpg/png/webp”).
- Downloads to `getTemporaryDirectory()/gutendex_covers/<id>.<ext>` and reuses if present.

### 5) Download + Import pipeline
Old app files:
- `lib/src/state/free_book_import_controller.dart`
- `lib/src/services/gutendex/epub_download_service.dart`
- `lib/src/state/library_controller.dart`

Pipeline:
1. User taps **Import**.
2. `FreeBookImportController`:
   - Checks “already imported” via `Book.gutenbergId`.
   - Throttles concurrent imports (`_maxConcurrentImports = 2`).
   - Downloads the EPUB to a **temporary file** with progress callbacks.
3. `EpubDownloadService`:
   - Streams download into `<tmp>/<name>.part`, then renames atomically.
   - Retries transient errors up to 3 times.
   - Enforces a per-chunk stream timeout (30s with no data).
4. `LibraryController.importBook(...)`:
   - Copies the file into the app’s `books/<bookId>/` directory.
   - Parses EPUB/PDF and creates a `Book` record.
   - Stores the Gutenberg id on the `Book` (`gutenbergId: book.id`).
5. Post-import: best-effort cover override
   - Attempts to download an image from Gutendex formats and writes `books/<bookId>/cover.<ext>`.
   - Updates the book’s `coverImagePath`.

### 6) UX qualities that made it “feel good”
- Per-book import state (idle/downloading/importing/done/failed) with progress bar.
- Concurrency cap to avoid CPU/IO spikes.
- Clean separation between:
  - API client + models
  - browsing/search controller
  - import controller
  - file download service
  - library import/persistence

---

## What exists in v2 today (gap analysis)

✅ `core_domain` already supports `Book.gutenbergId`.

Missing pieces:
- No Gutendex client/models in v2.
- No “Free books” UI route/screen.
- No shared import pipeline in app-layer (today the local file import logic lives in `LibraryScreen._handleImport`).
- No reusable “download to temp with progress + resume” specifically for EPUB import (but v2 has `ResilientDownloader`, used for TTS assets).

---

## Improvements to make (vs the previous app)

### Reliability / networking
- **Resume support** for large EPUBs (v1 had retry but not resume). Reuse `lib/utils/resilient_downloader.dart` in v2.
- Add **cancellation** (user leaves screen / taps cancel). At minimum: stop updating UI and clean temp files; ideally abort the stream.
- Prefer a single, consistent HTTP stack (avoid having multiple ad-hoc clients).

### Storage correctness
- Move Gutendex cover cache out of `TemporaryDirectory` (OS may clear it). Use:
  - `getApplicationSupportDirectory()` or v2’s `AppPaths` cache directory (and optionally implement size/TTL eviction).
- Avoid duplicate imports by enforcing uniqueness on `gutenbergId` at the “library write” boundary (not only in UI).

### UX / product
- If a book is already imported, show **Open** (or **Imported**) instead of a disabled Import, and deep link to `/book/:id`.
- Add filters (language, topic) later; keep first iteration minimal.

### Code structure
- Extract local import logic from `LibraryScreen` into an app-layer API so Gutenberg import and file picker import share the same pipeline.
- Consolidate “cover fetch” logic so we don’t maintain two parallel implementations.

---

## Implementation plan (v2)

### Proposed file layout (minimal + consistent)
- `lib/infra/gutendex/`
  - `gutendex_client.dart`
  - `gutendex_models.dart`
- `lib/app/gutenberg/`
  - `free_books_controller.dart` (top/search/pagination)
  - `gutenberg_import_controller.dart` (per-book import state + progress)
- `lib/ui/screens/free_books_screen.dart`
- (Refactor) `lib/app/library_controller.dart`
  - Add `importBookFromPath({required String sourcePath, required String fileName, int? gutenbergId})` or similar.
  - This becomes the single entry point for *all* imports.

### Step-by-step plan of attack

#### 1) Build Gutendex client + models
- Port the old `GutendexClient`/models nearly 1:1.
- Keep the `epubUrl` selection logic.
- Ensure queries include `mime_type=application/epub+zip` and `copyright=false`.

Acceptance:
- Can fetch a page and parse `count/next/results`.

#### 2) Implement browsing/search controller (Riverpod)
- Port `FreeBooksController` logic with stale-request protection.
- Keep “Top 100” cap initially.

Acceptance:
- UI can display top list + debounced search.

#### 3) Implement import controller (progress + concurrency cap)
- Port `FreeBookImportController` state shape (map keyed by Gutenberg id).
- Replace `EpubDownloadService` with v2 `ResilientDownloader` (resume/range support).
- Write downloads into a temp staging path under `AppPaths.tempDownloadsDir`.

Acceptance:
- Import button shows progress and ends in Imported/Failed state.

#### 4) Refactor: shared library import pipeline
- Move the file copy + EPUB parsing + `Book` creation out of `LibraryScreen` into `LibraryController`.
- Add `gutenbergId` plumbing (set on `Book`).

Acceptance:
- File-picker import still works.
- Gutenberg import uses the same library method.

#### 5) Add FreeBooksScreen + routing
- Add route `/free-books` in `lib/main.dart`.
- Add an entry point from `LibraryScreen` header (e.g., a “Free”/“Gutenberg” button).

Acceptance:
- You can browse/search and import from the new screen.

#### 6) Cover strategy (incremental)
- Prefer EPUB cover extracted by `EpubParser`.
- If no EPUB cover exists, optionally fetch a Gutendex cover and persist it under the book dir.
- Cache list thumbnails in a persistent cache directory.

Acceptance:
- List covers render reliably across app restarts.

#### 7) Tests (targeted)
- Unit tests for:
  - `GutendexBook.epubUrl` selection
  - `GutendexPage.fromJson` parsing
  - Import “already imported” behavior based on `gutenbergId`

---

## Risks / notes
- Gutendex is a public service; we should expect occasional downtime/slow requests and handle errors gracefully.
- EPUBs vary in quality; keep import errors user-friendly and don’t brick the library state.

---

## Reference (old project paths)
- Old project root (reference): `/home/william/Projects/audiobook_flutter/`
- Key old files:
  - `lib/src/screens/free_books_screen.dart`
  - `lib/src/state/free_books_controller.dart`
  - `lib/src/state/free_book_import_controller.dart`
  - `lib/src/services/gutendex/gutendex_client.dart`
  - `lib/src/services/gutendex/gutendex_models.dart`
  - `lib/src/services/gutendex/epub_download_service.dart`
  - `lib/src/services/gutendex/gutendex_image_fetcher.dart`
