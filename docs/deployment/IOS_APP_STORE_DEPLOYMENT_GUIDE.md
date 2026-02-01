# iOS App Store Deployment Guide

Complete guide for deploying the Audiobook Flutter app to the Apple App Store.

---

## Prerequisites

### Development Environment

- [ ] macOS with latest Xcode (15.0+)
- [ ] Apple Developer Program membership ($99/year)
- [ ] Physical iOS device for testing (iPhone 11+ recommended)
- [ ] Apple ID with two-factor authentication enabled

### Accounts Setup

1. **Apple Developer Account**: https://developer.apple.com
2. **App Store Connect**: https://appstoreconnect.apple.com
3. **Certificates, IDs & Profiles**: https://developer.apple.com/account/resources

---

## Phase 1: Certificate & Provisioning Setup

### 1.1 Create App ID

1. Go to **Certificates, Identifiers & Profiles** → **Identifiers**
2. Click **+** to create new identifier
3. Select **App IDs** → Continue
4. Select **App** → Continue
5. Fill in:
   - **Description**: Audiobook Flutter App
   - **Bundle ID**: `com.yourcompany.audiobook` (must match `ios/Runner.xcodeproj` bundle ID)
6. Enable capabilities:
   - [x] Audio, AirPlay, and Picture in Picture
   - [x] Background Modes (already in Info.plist)
7. Click **Register**

### 1.2 Create Distribution Certificate

1. Go to **Certificates** → Click **+**
2. Select **Apple Distribution** → Continue
3. Follow instructions to create CSR from Keychain Access:
   - Open **Keychain Access** → Certificate Assistant → Request a Certificate...
   - Enter email, common name, select "Saved to disk"
4. Upload CSR and download certificate
5. Double-click to install in Keychain

### 1.3 Create Provisioning Profile

1. Go to **Profiles** → Click **+**
2. Select **App Store Connect** → Continue
3. Select your App ID → Continue
4. Select your distribution certificate → Continue
5. Name it: `Audiobook Flutter Distribution`
6. Download and double-click to install

### 1.4 Configure Xcode

1. Open `ios/Runner.xcworkspace` in Xcode
2. Select **Runner** target → **Signing & Capabilities**
3. Set **Team** to your developer account
4. Ensure **Bundle Identifier** matches your App ID
5. Select the provisioning profile (or let Xcode manage automatically)

---

## Phase 2: App Store Connect Setup

### 2.1 Create App Record

1. Go to **App Store Connect** → **My Apps** → **+** → **New App**
2. Fill in:
   - **Platforms**: iOS
   - **Name**: Your app name (unique on App Store)
   - **Primary Language**: English (U.S.) or your choice
   - **Bundle ID**: Select your registered App ID
   - **SKU**: `audiobook-flutter-v1` (internal reference)
   - **User Access**: Full Access
3. Click **Create**

### 2.2 App Information

Navigate to **App Information** tab:

- **Privacy Policy URL**: Required - host on your website
- **Category**: Books (Primary), Education (Secondary)
- **Content Rights**: Confirm rights to app content
- **Age Rating**: Complete questionnaire (likely 4+ for audiobook reader)

### 2.3 Pricing and Availability

Navigate to **Pricing and Availability** tab:

- **Price**: Free (or select price tier)
- **Availability**: Select countries (usually all)
- **Pre-Orders**: Optional

### 2.4 App Privacy

Navigate to **App Privacy** tab:

Answer data collection questions:
- **Audio Files**: Collected (user imports their own books)
- **User Content**: Collected (bookmarks, reading progress)
- **Identifiers**: Not collected (no account system)
- **Usage Data**: Not collected (or minimal analytics)
- **Diagnostics**: Crash logs (if using Crashlytics)

---

## Phase 3: Build & Upload

### 3.1 Update Version Numbers

Edit `pubspec.yaml`:
```yaml
version: 1.0.0+1  # version+buildNumber
```

The build number must increment with each upload.

### 3.2 Build Release IPA

```bash
# Clean previous builds
flutter clean

# Get dependencies
flutter pub get

# Build release IPA
flutter build ipa --release

# Output location: build/ios/ipa/Runner.ipa
```

### 3.3 Validate Build in Xcode

1. Open `ios/Runner.xcworkspace` in Xcode
2. Select **Product** → **Archive**
3. Wait for archive to complete
4. In **Organizer** window, select archive → **Validate App**
5. Fix any validation errors

### 3.4 Upload to App Store Connect

**Option A: Via Xcode**
1. In Organizer, select archive → **Distribute App**
2. Select **App Store Connect** → **Upload**
3. Follow prompts (signing, export compliance, etc.)

**Option B: Via Transporter**
1. Download [Transporter](https://apps.apple.com/app/transporter/id1450874784) from Mac App Store
2. Drag & drop `build/ios/ipa/Runner.ipa`
3. Click **Deliver**

**Option C: Via Command Line**
```bash
xcrun altool --upload-app \
  --type ios \
  --file build/ios/ipa/Runner.ipa \
  --username "your@email.com" \
  --password "@keychain:AC_PASSWORD"
```

---

## Phase 4: TestFlight Testing

### 4.1 Configure TestFlight

1. In App Store Connect, go to **TestFlight** tab
2. Wait for build processing (5-30 minutes)
3. Answer export compliance question:
   - Uses encryption: **No** (standard HTTPS only)
4. Build becomes available for testing

### 4.2 Internal Testing

1. Go to **Internal Testing** → **+** to create group
2. Add internal testers (up to 100)
3. Testers receive TestFlight invite email
4. They install via TestFlight app

### 4.3 External Beta Testing (Optional)

1. Go to **External Testing** → **+** to create group
2. Fill out **Test Information**:
   - Beta App Description
   - Feedback Email
   - Marketing URL (optional)
3. Add up to 10,000 external testers
4. Submit for **Beta App Review** (usually quick)

### 4.4 Test Checklist for Testers

Provide testers with this checklist:

```markdown
## iOS TestFlight Testing Checklist

### Basic Functionality
- [ ] App launches without crash
- [ ] Library screen displays correctly
- [ ] Can import EPUB book
- [ ] Can import PDF book

### TTS Synthesis
- [ ] Can download Piper voice model
- [ ] Can download Kokoro voice model  
- [ ] Can download Supertonic voice model
- [ ] Text-to-speech plays correctly
- [ ] Audio quality is acceptable

### Playback
- [ ] Playback controls work (play/pause/skip)
- [ ] Chapter navigation works
- [ ] Speed control works
- [ ] Background playback continues
- [ ] Lock screen controls work
- [ ] Bluetooth headphone controls work

### Edge Cases
- [ ] Phone call interrupts playback gracefully
- [ ] App resumes after interruption
- [ ] No crashes during 30min continuous use
- [ ] Memory usage stays reasonable

### Report Issues
Email: support@yourcompany.com
Include: device model, iOS version, steps to reproduce
```

---

## Phase 5: App Store Submission

### 5.1 Screenshots

Required sizes:
- **6.7" (iPhone 15 Pro Max)**: 1290 x 2796 pixels
- **6.5" (iPhone 11 Pro Max)**: 1284 x 2778 pixels
- **5.5" (iPhone 8 Plus)**: 1242 x 2208 pixels
- **12.9" iPad Pro**: 2048 x 2732 pixels

Screenshot content (for each device size):
1. Library screen showing imported books
2. Book details with chapter list
3. Playback screen during synthesis
4. Settings/voice download screen

Tools:
- Xcode Simulator for clean screenshots
- Figma/Sketch for adding device frames and text

### 5.2 App Preview Video (Optional)

- 15-30 seconds showing key features
- Capture directly from device (QuickTime Player → New Movie Recording)
- Upload same video for all device sizes

### 5.3 Store Listing Content

**App Name** (30 chars max):
```
Audiobook Reader - AI Voice
```

**Subtitle** (30 chars max):
```
Listen to your books with AI
```

**Promotional Text** (170 chars, can change anytime):
```
Transform any book into an audiobook with AI-powered text-to-speech. 
Choose from multiple natural voices. Listen anywhere, anytime.
```

**Description** (4000 chars max):
```
Turn your EPUB and PDF books into audiobooks with advanced AI text-to-speech technology.

FEATURES:
• Import EPUB and PDF files from your device
• Three AI voice engines: Kokoro, Piper, and Supertonic
• Multiple natural-sounding voices
• Background playback support
• Lock screen and headphone controls
• Chapter-by-chapter navigation
• Adjustable playback speed

HOW IT WORKS:
1. Import your book (EPUB or PDF)
2. Download a voice model (first time only)
3. Press play and listen!

PRIVACY:
All processing happens on your device. Your books never leave your phone.
We don't collect personal data or track your reading habits.

SUPPORTED FORMATS:
• EPUB (.epub)
• PDF (.pdf)

REQUIREMENTS:
• iOS 14.0 or later
• 200MB+ free space for voice models
• Works offline after voice download
```

**Keywords** (100 chars, comma-separated):
```
audiobook,text to speech,tts,ebook,epub,pdf,ai voice,book reader,listen,narrator
```

### 5.4 Review Information

**Contact Information:**
- First Name: Your name
- Last Name: Your name
- Phone: Your phone
- Email: your@email.com

**Notes for Review:**
```
This app uses on-device AI to convert books to speech. 

TESTING INSTRUCTIONS:
1. Launch the app
2. Tap "Import Book" and select the included sample EPUB
3. Tap "Download" on any voice to get a voice model (~50-100MB)
4. Tap "Play" to hear the AI-generated audio

The app requires downloading voice models (50-100MB each) on first use.
All processing happens on-device - no server communication for TTS.

If you need a test book file, sample EPUBs are available at:
https://www.gutenberg.org/ebooks/
```

**Demo Account:** Not applicable (no login required)

### 5.5 Submit for Review

1. Go to **App Store** tab → select your build
2. Verify all sections are complete (green checkmarks)
3. Click **Add for Review**
4. Answer submission questions:
   - Content rights: Yes
   - Advertising identifier: No (unless using ads)
   - Export compliance: No encryption beyond HTTPS
5. Click **Submit to App Review**

---

## Phase 6: Review Process

### 6.1 Timeline

- **Initial Review**: Usually 24-48 hours
- **Rejection Response**: Varies (can be same day or several days)
- **Re-review After Fix**: Usually faster than initial

### 6.2 Common Rejection Reasons

**Performance Issues:**
- App crashes on launch → Test on multiple iOS versions
- Slow startup → Optimize initialization

**Design Issues:**
- Placeholder content → Use real screenshots/icons
- Broken links → Test all URLs

**Legal Issues:**
- Missing privacy policy → Add URL in App Information
- Copyright concerns → Ensure you have rights to all content

**Metadata Issues:**
- Inaccurate screenshots → Capture from actual app
- Misleading description → Match actual functionality

### 6.3 Responding to Rejection

1. Read rejection reason carefully in **Resolution Center**
2. Fix the issue in your code/metadata
3. Upload new build (increment build number)
4. Reply in Resolution Center explaining the fix
5. Resubmit for review

---

## Phase 7: Post-Release

### 7.1 Monitor App Analytics

App Store Connect provides:
- Downloads by day/country
- Active devices
- Crashes (via App Analytics)
- Sales and trends

### 7.2 Respond to Reviews

1. Go to **App Store Connect** → **Reviews**
2. Reply to user reviews professionally
3. Thank positive reviewers
4. Address negative feedback with solutions

### 7.3 Release Updates

For app updates:
1. Increment version in `pubspec.yaml`
2. Build and upload new IPA
3. Create new version in App Store Connect
4. Fill in "What's New" section
5. Submit for review

---

## Quick Reference

### Key URLs

| Resource | URL |
|----------|-----|
| Developer Portal | https://developer.apple.com |
| App Store Connect | https://appstoreconnect.apple.com |
| TestFlight | https://testflight.apple.com |
| App Review Guidelines | https://developer.apple.com/app-store/review/guidelines/ |
| Human Interface Guidelines | https://developer.apple.com/design/human-interface-guidelines/ |

### Build Commands

```bash
# Clean and rebuild
flutter clean && flutter pub get

# Build iOS release
flutter build ipa --release

# Check build size
du -sh build/ios/ipa/Runner.ipa

# Open in Xcode (for archive/upload)
open ios/Runner.xcworkspace
```

### Xcode Keyboard Shortcuts

- **Archive**: ⌘ + Shift + Option + R (after Product → Archive)
- **Organizer**: ⌘ + Option + Shift + O
- **Clean Build**: ⌘ + Shift + K

---

## Troubleshooting

### Build Fails

**"No provisioning profiles found"**
- Download profiles from developer portal
- Or let Xcode manage signing automatically

**"Code signing error"**
- Ensure certificate is installed in Keychain
- Check certificate hasn't expired

### Upload Fails

**"Invalid binary"**
- Ensure minimum iOS version matches
- Check for simulator architectures (strip them)

**"Missing compliance"**
- Answer export compliance in App Store Connect

### Review Rejected

**"Guideline 2.1 - Performance"**
- App must not crash
- Test thoroughly on actual devices

**"Guideline 4.2 - Design"**
- Must have sufficient features
- Not just a web wrapper

---

## Current Status Checklist

### Completed
- [x] Info.plist configured (background audio, file sharing)
- [x] iOS deployment target set (14.0)
- [x] App icons configured
- [x] TTS engines implemented (Kokoro, Piper, Supertonic)
- [x] sherpa-onnx integrated
- [x] ONNX Runtime Supertonic implemented (replaced CoreML)
- [x] Device testing passed (all engines work)

### Pending
- [ ] Apple Developer account setup
- [ ] App ID registration
- [ ] Distribution certificate
- [ ] Provisioning profile
- [ ] App Store Connect app record
- [ ] TestFlight build
- [ ] Internal testing
- [ ] Screenshots
- [ ] Store listing content
- [ ] Privacy policy URL
- [ ] Submit for review

---

*Document created: 2026-01-24*
*App version: 1.0.0*
