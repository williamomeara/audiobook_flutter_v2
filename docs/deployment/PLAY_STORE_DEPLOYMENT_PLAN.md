# Play Store Deployment Plan

Step-by-step actionable plan for deploying Éist to Google Play Store.

---

## Phase 1: Code Preparation (Before Building)

### 1.1 Commit Pending Changes
- [ ] Review and commit current uncommitted changes (8 files pending)
- [ ] Merge feature branch to main (or create release branch)
- [ ] Tag the release: `git tag -a v1.0.0 -m "First Play Store release"`

### 1.2 Fix Package Name (CRITICAL)
The current package name `com.example.audiobook_flutter_v2` is a placeholder and will be **rejected by Play Store**.

- [ ] Choose a unique package name (e.g., `com.yourname.eist` or `io.eist.app`)
- [ ] Update `android/app/build.gradle.kts`:
  ```kotlin
  applicationId = "com.yourname.eist"  // Your chosen package name
  namespace = "com.yourname.eist"
  ```
- [ ] Update `android/app/src/main/AndroidManifest.xml` if any hardcoded references exist
- [ ] Run `flutter clean && flutter pub get`

### 1.3 Update Version Info
- [ ] Update `pubspec.yaml`:
  ```yaml
  version: 1.0.0+1  # format: major.minor.patch+buildNumber
  ```
  - `versionName` = 1.0.0 (shown to users)
  - `versionCode` = 1 (internal, must increment each release)

---

## Phase 2: Signing Configuration

### 2.1 Create Upload Keystore
This keystore is used to sign your app bundle. **NEVER lose this or you can't update your app.**

```bash
# Run in terminal
keytool -genkey -v -keystore ~/eist-upload-keystore.jks \
  -storetype JKS -keyalg RSA -keysize 2048 -validity 10000 \
  -alias upload
```
- [ ] Store keystore securely (backup to secure location)
- [ ] Note the keystore password and key password

### 2.2 Create key.properties
Create `android/key.properties` (DO NOT commit to git):

```properties
storePassword=<your_keystore_password>
keyPassword=<your_key_password>
keyAlias=upload
storeFile=/absolute/path/to/eist-upload-keystore.jks
```

- [ ] Create the file
- [ ] Add to `.gitignore`: `android/key.properties`

### 2.3 Configure Gradle for Signing
Update `android/app/build.gradle.kts`:

```kotlin
// Add at the top, after plugins
import java.util.Properties
import java.io.FileInputStream

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    // ... existing config ...
    
    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String?
            keyPassword = keystoreProperties["keyPassword"] as String?
            storeFile = keystoreProperties["storeFile"]?.let { file(it) }
            storePassword = keystoreProperties["storePassword"] as String?
        }
    }
    
    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            // ... rest of release config ...
        }
    }
}
```

- [ ] Update build.gradle.kts
- [ ] Verify signing works: `flutter build appbundle --release`

---

## Phase 3: Build Release Bundle

### 3.1 Clean Build
```bash
flutter clean
flutter pub get
flutter build appbundle --release
```

- [ ] Build completes without errors
- [ ] AAB file created at `build/app/outputs/bundle/release/app-release.aab`

### 3.2 Verify Bundle
```bash
# Check bundle size
ls -lh build/app/outputs/bundle/release/app-release.aab

# Optional: Test APK from bundle
bundletool build-apks --bundle=build/app/outputs/bundle/release/app-release.aab \
  --output=test.apks --mode=universal
```

- [ ] Bundle size is reasonable (< 150MB recommended)
- [ ] App installs and runs correctly from bundle

---

## Phase 4: Play Console Setup

### 4.1 Create Developer Account
- [ ] Go to [Google Play Console](https://play.google.com/console)
- [ ] Pay $25 one-time registration fee
- [ ] Complete identity verification (may take 48 hours)

### 4.2 Create App
- [ ] Click "Create app"
- [ ] Enter app name: "Éist"
- [ ] Select "App" (not game)
- [ ] Select "Free" or "Paid"
- [ ] Accept developer policies

### 4.3 App Signing (Let Google Manage)
- [ ] Go to Setup > App signing
- [ ] Choose "Let Google manage and protect your app signing key"
- [ ] Upload your AAB - Google will handle key rotation

---

## Phase 5: Store Listing

### 5.1 Main Store Listing
- [ ] **App name**: Éist (or "Éist - Audiobook TTS")
- [ ] **Short description** (80 chars): AI-powered audiobook reader with natural text-to-speech
- [ ] **Full description** (4000 chars): Write compelling description
  - Key features: AI TTS, multiple engines, offline playback, EPUB/PDF support
  - Unique selling points: Kokoro/Piper/Supertonic voices
  - How it works

### 5.2 Graphics
- [ ] **App icon** (512x512): High-res version of launcher icon
- [ ] **Feature graphic** (1024x500): Banner for Play Store listing
- [ ] **Screenshots** (min 2, max 8 per device type):
  - Phone screenshots (16:9 or 9:16)
  - Tablet screenshots (optional but recommended)
  - Recommended screens: Library, Playback, Settings, Voice Download

### 5.3 Categorization
- [ ] **App category**: Books & Reference
- [ ] **Tags**: audiobook, tts, text-to-speech, ebook reader

---

## Phase 6: Content & Policies

### 6.1 Content Rating
Complete the content rating questionnaire:
- [ ] Answer all questions honestly
- [ ] Expected rating: Everyone (E) or 10+ depending on content
- [ ] Submit questionnaire

### 6.2 Target Audience
- [ ] Target age: 18+ (simplest for new apps)
  - Targeting under 13 requires compliance with COPPA
- [ ] App designed for children: No

### 6.3 Data Safety
Complete the Data Safety form:
- [ ] **Data collection**: 
  - Does the app collect/share user data? (Likely: No, unless analytics)
  - Book files stay on device
- [ ] **Data types** (if applicable):
  - Personal info: No
  - Financial info: No
  - Device/usage data: Only if analytics enabled
- [ ] **Security practices**:
  - Data encrypted in transit: Yes (model downloads use HTTPS)
  - Data deletion request: N/A if no collection

### 6.4 Privacy Policy
- [ ] Create privacy policy document
- [ ] Host at public URL (GitHub Pages, website, etc.)
- [ ] Include:
  - What data is collected (none/minimal)
  - How data is used
  - Third-party services (none)
  - Contact information
- [ ] Enter URL in Play Console

---

## Phase 7: Testing

### 7.1 Internal Testing Track
- [ ] Go to Testing > Internal testing
- [ ] Create new release
- [ ] Upload AAB
- [ ] Add testers (email addresses)
- [ ] Publish to internal track
- [ ] Share testing link with testers

### 7.2 Test on Multiple Devices
- [ ] Test on low-end device (older/budget phone)
- [ ] Test on high-end device
- [ ] Test on tablet (if screenshots provided)
- [ ] Verify TTS downloads work
- [ ] Verify playback works
- [ ] Check for crashes (Play Console vitals)

### 7.3 Pre-launch Report
- [ ] Review Play Console's pre-launch report
- [ ] Fix any critical issues found
- [ ] Address accessibility warnings (if any)

---

## Phase 8: Production Release

### 8.1 Final Review
- [ ] All store listing fields completed
- [ ] All required graphics uploaded
- [ ] Content rating complete
- [ ] Data safety section complete
- [ ] Privacy policy URL entered
- [ ] At least one testing round completed

### 8.2 Create Production Release
- [ ] Go to Production > Create new release
- [ ] Upload AAB (or promote from internal track)
- [ ] Write release notes
- [ ] Review and start rollout

### 8.3 Rollout Strategy
- [ ] Start with staged rollout (10-20%)
- [ ] Monitor crash rate and reviews
- [ ] Gradually increase to 100%

---

## Phase 9: Post-Launch

### 9.1 Monitoring
- [ ] Set up crash reporting (Firebase Crashlytics recommended)
- [ ] Monitor Play Console vitals
- [ ] Check for ANRs (App Not Responding)
- [ ] Monitor user reviews

### 9.2 Response Plan
- [ ] Respond to user reviews
- [ ] Track feature requests
- [ ] Plan update cadence

---

## Quick Checklist Summary

**Must-have before submission:**
1. [ ] Unique package name (not com.example.*)
2. [ ] Signed release build
3. [ ] App icon (512x512)
4. [ ] Feature graphic (1024x500)
5. [ ] At least 2 phone screenshots
6. [ ] Short and full description
7. [ ] Privacy policy URL
8. [ ] Content rating completed
9. [ ] Data safety completed
10. [ ] Internal testing passed

**Nice-to-have:**
- Tablet screenshots
- Video preview
- Multiple language listings
- Promotional text

---

## Estimated Timeline

| Phase | Duration |
|-------|----------|
| Code prep & signing | 1-2 hours |
| Build & test | 1 hour |
| Play Console setup | 2-3 hours |
| Store listing & graphics | 2-4 hours |
| Internal testing | 1-3 days |
| Review process | 1-7 days |

**Total: ~1-2 weeks** (including review time)

---

## Important Notes

1. **Package name is permanent** - Once published, you cannot change it
2. **Keep keystore safe** - Losing it means creating a new app
3. **Reviews take time** - First review may take 7+ days
4. **Staged rollouts** - Use them to catch issues early
5. **Version codes always increase** - Can't reuse or decrease

---

*Related docs: [APP_STORE_RELEASE_CHECKLIST.md](../APP_STORE_RELEASE_CHECKLIST.md)*
