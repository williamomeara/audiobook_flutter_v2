# Pre-Release Preparation Checklist

**Status:** ✅ Complete  
**Date:** January 29, 2026

---

## 1.1 Code Preparation

- [x] **Remove debug code**
  - No print statements found in `lib/`
  - Release mode builds work correctly

- [x] **Version number set**
  - `version: 1.0.0+1` in pubspec.yaml

- [x] **ProGuard/R8 configured**
  - `android/app/proguard-rules.pro` updated with:
    - Audio service classes preserved
    - Sherpa-onnx classes preserved  
    - Google Play Billing classes preserved
    - RevenueCat classes preserved

- [x] **Signing keys created**
  - Keystore: `~/.android-keystores/audiobook-upload-key.jks`
  - Key alias: `upload`
  - Validity: 10,000 days
  - **⚠️ IMPORTANT:** Change passwords before production release!

---

## 1.2 Privacy Policy & Terms

- [x] **Privacy Policy created**
  - File: `docs/legal/privacy_policy.md`
  - Covers: data collection, TTS processing, local storage, analytics
  - **TODO:** Host at https://eist.app/privacy-policy

- [x] **Terms of Service created**
  - File: `docs/legal/terms_of_service.md`
  - Covers: subscription terms, refund policy, content rights
  - **TODO:** Host at https://eist.app/terms

---

## 1.3 Android Configuration

- [x] **build.gradle.kts updated**
  - Release signing configuration added
  - Uses `key.properties` file
  - ProGuard enabled for release builds

- [x] **AndroidManifest.xml updated**
  - Billing permission added: `com.android.vending.BILLING`
  - All required permissions present

- [x] **key.properties created** (gitignored)
  - Path: `android/key.properties`
  - Contains: storePassword, keyPassword, keyAlias, storeFile

---

## 1.4 Release Build Verified

- [x] **App Bundle builds successfully**
  - Command: `flutter build appbundle --release`
  - Output: `build/app/outputs/bundle/release/app-release.aab`
  - Size: ~115 MB

---

## 1.5 Required Assets (Pending)

- [ ] **App Icon** (512x512 PNG)
- [ ] **Feature Graphic** (1024x500 PNG)
- [ ] **Phone Screenshots** (1080x1920, min 2)
- [ ] **Tablet Screenshots** (1920x1200, optional)

See: `docs/deployment/store_assets_spec.md`

---

## Files Created/Modified

| File | Status |
|------|--------|
| `android/app/build.gradle.kts` | Modified - signing config |
| `android/app/proguard-rules.pro` | Modified - billing rules |
| `android/app/src/main/AndroidManifest.xml` | Modified - billing permission |
| `android/key.properties` | Created (gitignored) |
| `docs/legal/privacy_policy.md` | Created |
| `docs/legal/terms_of_service.md` | Created |
| `docs/deployment/store_assets_spec.md` | Created |
| `assets/store/` | Directory created |

---

## Security Notes

⚠️ **Before production release:**

1. **Change keystore passwords** from temporary values
2. **Back up keystore** to secure location (cannot recover if lost!)
3. **Never commit** key.properties or keystore to git
4. **Enable Play App Signing** for automatic key management

---

## Next Step

Proceed to **Phase 2: Google Play Developer Account Setup**

See: `docs/deployment/google_play_release_plan.md`
