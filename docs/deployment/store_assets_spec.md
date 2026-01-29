# Play Store Assets Specification

This document specifies the required assets for Google Play Store listing.

## Required Assets

### App Icon
- **File:** `assets/store/app_icon_512.png`
- **Size:** 512 x 512 pixels
- **Format:** PNG (32-bit, no transparency recommended)
- **Status:** ❌ Needs creation

### Feature Graphic
- **File:** `assets/store/feature_graphic.png`
- **Size:** 1024 x 500 pixels
- **Format:** PNG or JPEG
- **Purpose:** Appears at the top of the store listing
- **Status:** ❌ Needs creation

### Phone Screenshots (Required - minimum 2)
- **Directory:** `assets/store/screenshots/phone/`
- **Size:** 1080 x 1920 pixels (portrait) or 1920 x 1080 (landscape)
- **Format:** PNG or JPEG
- **Quantity:** 2-8 screenshots

Suggested screenshots:
1. `library_view.png` - Library with imported books
2. `playback_screen.png` - Playback controls and waveform
3. `book_details.png` - Chapter list and book info
4. `voice_selection.png` - Voice picker showing available voices
5. `settings.png` - Settings and customization options

**Status:** ❌ Needs creation

### Tablet Screenshots (Recommended)
- **Directory:** `assets/store/screenshots/tablet/`
- **Size:** 1920 x 1200 pixels or 2560 x 1600 pixels
- **Format:** PNG or JPEG
- **Quantity:** 2-8 screenshots

**Status:** ❌ Needs creation (optional but recommended)

### Promotional Video (Optional)
- **URL:** YouTube video link
- **Duration:** 30 seconds - 2 minutes
- **Content:** App demo showing key features
- **Status:** ❌ Not created (optional)

---

## Asset Creation Guidelines

### App Icon Design
- Clean, simple design
- Works at small sizes
- Represents audiobook/reading concept
- Consider Material Design guidelines

### Screenshots Guidelines
- Show actual app UI (not mockups)
- Use device frames for polish
- Include short captions if desired
- Highlight key features
- Use consistent style across all screenshots

### Feature Graphic Guidelines
- Eye-catching design
- Include app name/logo
- Brief tagline (e.g., "Turn Any Book Into an Audiobook")
- High-quality graphics

---

## Directory Structure to Create

```
assets/
└── store/
    ├── app_icon_512.png
    ├── feature_graphic.png
    └── screenshots/
        ├── phone/
        │   ├── 01_library.png
        │   ├── 02_playback.png
        │   ├── 03_book_details.png
        │   ├── 04_voices.png
        │   └── 05_settings.png
        └── tablet/
            ├── 01_library.png
            └── 02_playback.png
```

---

## Capturing Screenshots

### Using scrcpy
```bash
# Take screenshot
adb exec-out screencap -p > screenshot.png

# Or use scrcpy recording
scrcpy --record file.mp4
```

### Using Android Studio
1. Open Device File Explorer
2. Navigate to /sdcard/Pictures/Screenshots
3. Pull screenshots to computer

### Tips
- Use a clean device (no notifications visible)
- Fill library with sample books with nice covers
- Set light mode or dark mode consistently
- Capture at highest quality available

---

## Next Steps

1. [ ] Create app icon (512x512)
2. [ ] Create feature graphic (1024x500)
3. [ ] Capture 5 phone screenshots (1080x1920)
4. [ ] (Optional) Capture 2 tablet screenshots
5. [ ] (Optional) Create promotional video

Save all files to `assets/store/` directory.
