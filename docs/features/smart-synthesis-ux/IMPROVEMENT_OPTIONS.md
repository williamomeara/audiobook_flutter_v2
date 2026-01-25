# Smart Synthesis UX Improvements

## Current Behavior

### Toggle: "Smart synthesis"
**What users think it does:** Enable/disable audio synthesis optimization  
**What it actually does:**
- **ON:** Cold-start pre-synthesis (2 segments ready before play) + extended prefetch (5+ segments ahead)
- **OFF:** Still prefetches 1 segment ahead while current plays, just no cold-start optimization

**Problem:** Toggle OFF still provides seamless playback (no gaps), making the setting appear to do nothing.

### Segment Colors
**Purpose:** Visual feedback showing which segments are ready to play (cached)
**Current accuracy:**
- ✅ Accurate at chapter load (checks actual cache)
- ✅ Accurate during synthesis (updates via callbacks)
- ⚠️ NOT accurate if cache evicts segments during playback

---

## Improvement Options

### Option 1: Rename the Toggle

**Change:** "Smart synthesis" → "Pre-buffer audio"

**New subtext:** "Load several segments ahead for uninterrupted playback"

**UX Improvement:**
- Clearer what the setting does
- Aligns user expectations with actual behavior
- Reduces support questions like "What's the difference?"

**Effort:** Low (text change only)

**When OFF:**
- Still works smoothly (immediate next-segment prefetch remains)
- User saves some battery/memory (less prefetching)

---

### Option 2: Remove Toggle Entirely

**Change:** Remove "Smart synthesis" toggle from Settings

**UX Improvement:**
- One less confusing option
- Prefetching is universally beneficial
- Simplifies settings screen

**Effort:** Low (remove toggle + setting)

**Trade-off:** 
- Power users lose ability to reduce battery usage
- Could add back as Developer option if needed

---

### Option 3: Make Toggle Control ALL Prefetching

**Change:** When OFF, disable immediate next-segment prefetch too

**UX Improvement:**
- Setting now has visible effect (gaps between segments)
- Useful for debugging or demonstrating the feature's value
- Maximum battery savings when OFF

**Effort:** Medium (code change in playback_controller.dart)

**Risk:**
- Poor user experience when OFF (playback stutters)
- Users might accidentally disable and blame the app

---

### Option 4: Add Cache Verification for Colors

**Change:** Periodically verify segment colors match actual cache state

**Implementation:**
- Every 5 segments played, check if upcoming 10 segments still exist in cache
- If cache evicted a segment, update tracker (change color back to "not ready")

**UX Improvement:**
- Segment colors are always accurate
- Users can trust the visual feedback
- No "surprise" when playing a segment that was supposedly ready

**Effort:** Medium (add verification logic, wire to tracker)

**When it matters:**
- Long listening sessions where cache fills up
- Users with small cache quota settings

---

### Option 5: Cache Eviction Callbacks

**Change:** IntelligentCacheManager notifies tracker when segments are evicted

**Implementation:**
- Add callback mechanism to cache manager
- Register listener in PlaybackControllerNotifier
- Update tracker immediately on eviction

**UX Improvement:**
- Real-time color accuracy (no delay)
- Most robust solution
- Colors update the moment cache changes

**Effort:** High (requires changes to cache manager, playback providers, tracker)

**Benefit over Option 4:**
- Immediate feedback vs periodic polling
- Lower battery (no constant checking)

---

## Recommendation Matrix

| Option | UX Impact | Effort | Recommended? |
|--------|-----------|--------|--------------|
| 1. Rename toggle | Low | Low | ✅ Yes - quick win |
| 2. Remove toggle | Medium | Low | 🤔 Maybe - simplifies UI |
| 3. Full prefetch control | Medium | Medium | ❌ No - hurts UX when OFF |
| 4. Periodic verification | Medium | Medium | ✅ Yes - good accuracy |
| 5. Eviction callbacks | High | High | 🤔 Maybe - if perfection needed |

## Suggested Implementation Order

1. **Phase 1 (Quick Win):** Rename toggle to "Pre-buffer audio"
2. **Phase 2 (Nice to Have):** Add periodic cache verification
3. **Phase 3 (If Needed):** Eviction callbacks for real-time accuracy

---

## Impact Summary

| Improvement | User Benefit |
|-------------|--------------|
| Renamed toggle | "Now I understand what this setting does!" |
| Accurate colors | "I can trust the visual - if it's colored, it's ready" |
| Removed toggle | "Fewer settings to worry about, just works" |
