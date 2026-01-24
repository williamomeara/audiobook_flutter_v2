# App Store Release Checklist

Comprehensive checklist for releasing the Audiobook Flutter app on both Google Play Store and Apple App Store.

---

## Pre-Release Technical Validation

### iOS Device Testing
- [ ] Run integration tests on physical iOS device
  ```bash
  flutter test integration_test/tts_synthesis_test.dart -d <ios_device_id>
  ```
- [ ] Verify Piper TTS synthesis works
- [ ] Verify Kokoro TTS synthesis works  
- [ ] Verify Supertonic TTS synthesis works
- [ ] Test model downloads over Wi-Fi
- [ ] Test model downloads over cellular
- [ ] Test background playback (audio continues when app minimized)
- [ ] Test lock screen controls (play/pause/skip)
- [ ] Test Bluetooth headphone controls
- [ ] Test phone call interruption handling
- [ ] 1-hour continuous playback test (no crashes)

### Android Regression Testing
- [ ] Run integration tests on Android device
- [ ] Verify all TTS engines still work after iOS changes
- [ ] Test background playback
- [ ] Verify no new crashes introduced

---

## App Store Assets

### App Icons
- [x] iOS icons (all sizes in Assets.xcassets) ✅
- [x] Android icons (adaptive icons configured) ✅

### Screenshots
- [ ] iOS screenshots (iPhone 17 Pro)
  - [ ] Library screen
  - [ ] Book details screen
  - [ ] Playback screen
  - [ ] Settings/voice download screen
- [ ] iOS screenshots (iPad Pro)
  - [ ] Same screens as iPhone
- [ ] Android screenshots (Pixel phone)
  - [ ] Same screens as iPhone
- [ ] Android screenshots (Tablet)
  - [ ] Same screens as iPhone

### App Store Listing
- [ ] App name finalized
- [ ] Short description (80 chars max)
- [ ] Full description (4000 chars max)
- [ ] Keywords/tags
- [ ] App category (Books / Education)
- [ ] Content rating questionnaire completed

### Promotional Assets
- [ ] Feature graphic (1024x500) - Google Play
- [ ] App preview video (optional)
- [ ] Promotional text (170 chars) - App Store

---

## Legal & Compliance

### Privacy
- [ ] Privacy policy URL created and hosted
- [ ] Privacy policy linked in app settings
- [ ] Data safety form completed (Google Play)
- [ ] App privacy details completed (App Store)

### Licenses
- [ ] Open source licenses displayed in app
- [ ] sherpa-onnx license (Apache 2.0) included
- [ ] ONNX Runtime license included
- [ ] All Flutter package licenses included

### Age Rating
- [ ] ESRB/PEGI rating obtained (if required)
- [ ] Content rating questionnaire accurate

---

## App Store Specific

### Apple App Store

#### Developer Account
- [ ] Apple Developer Program membership ($99/year)
- [ ] App ID registered in Apple Developer Portal
- [ ] Provisioning profiles created (distribution)
- [ ] Signing certificates configured

#### App Store Connect
- [ ] App record created in App Store Connect
- [ ] App information completed
- [ ] Pricing set (Free or Paid)
- [ ] Availability regions selected
- [ ] In-app purchases configured (if any)

#### Review Preparation
- [ ] Demo account credentials (if login required)
- [ ] Notes for reviewers (TTS model downloads, etc.)
- [ ] Contact information for review questions

#### TestFlight
- [ ] Internal testing group created
- [ ] TestFlight build uploaded
- [ ] Internal testers invited
- [ ] At least 1 round of TestFlight testing complete
- [ ] External beta testing (optional)

#### Submission
- [ ] All screenshots uploaded
- [ ] App preview video uploaded (optional)
- [ ] Build selected for review
- [ ] Export compliance confirmed
- [ ] Submit for review

### Google Play Store

#### Developer Account
- [ ] Google Play Developer account ($25 one-time)
- [ ] Developer profile completed
- [ ] Payment profile set up (if monetizing)

#### Play Console
- [ ] App created in Play Console
- [ ] Store listing completed
- [ ] Content rating completed
- [ ] Target audience selected
- [ ] Data safety section completed

#### App Signing
- [ ] App signing by Google Play enabled
- [ ] Upload key created and secured
- [ ] Keystore backed up securely

#### Testing Tracks
- [ ] Internal testing track set up
- [ ] Internal testers added
- [ ] AAB uploaded to internal track
- [ ] Testing feedback collected
- [ ] Closed/Open beta testing (optional)

#### Production Release
- [ ] All pre-launch report issues resolved
- [ ] Production release created
- [ ] Countries selected for rollout
- [ ] Staged rollout percentage set (10-20% recommended)
- [ ] Submit for review

---

## Build & Release

### iOS Release Build
- [ ] Version number updated (pubspec.yaml)
- [ ] Build number incremented
- [ ] Release build created
  ```bash
  flutter build ipa --release
  ```
- [ ] IPA file size acceptable (current: ~87MB)
- [ ] Build validated in Xcode

### Android Release Build
- [ ] Version number matches iOS
- [ ] Build number incremented
- [ ] Release AAB created
  ```bash
  flutter build appbundle --release
  ```
- [ ] AAB signed correctly
- [ ] AAB size acceptable

### Version Control
- [ ] All changes committed
- [ ] Feature branch merged to main
- [ ] Release tag created
  ```bash
  git tag -a v1.0.0 -m "First production release"
  git push origin v1.0.0
  ```

---

## Post-Release

### Monitoring
- [ ] Crashlytics/Firebase configured
- [ ] App Store analytics enabled
- [ ] Play Console vitals monitoring
- [ ] Review monitoring set up

### Support
- [ ] Support email configured
- [ ] FAQ/Help documentation
- [ ] Bug report process documented

---

## Current Status

| Platform | Status | Blocker |
|----------|--------|---------|
| iOS | 90% Ready | Device testing pending |
| Android | Production Ready | None |

### iOS Remaining Tasks
1. Physical device testing (synthesis, downloads, playback)
2. TestFlight build and testing
3. App Store Connect setup
4. Screenshot capture
5. Submit for review

### Android Remaining Tasks
1. Regression testing
2. Screenshot capture
3. Play Console listing completion
4. Submit for review

---

*Last updated: {{current_date}}*
