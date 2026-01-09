# App Store Deployment Guide

## Overview

This guide covers all steps required to publish the audiobook app on both the Apple App Store (iOS) and Google Play Store (Android). Follow each section in order, checking off items as they are completed.

---

## Table of Contents

1. [Pre-Deployment Checklist](#pre-deployment-checklist)
2. [App Configuration](#app-configuration)
3. [Android Deployment](#android-deployment)
4. [iOS Deployment](#ios-deployment)
5. [Monetization Implementation](#monetization-implementation)
6. [Marketing & Store Listings](#marketing--store-listings)
7. [Final Testing](#final-testing)
8. [Submission](#submission)
9. [Post-Launch](#post-launch)

---

## Pre-Deployment Checklist

### Code Quality

- [ ] All lint warnings resolved (`flutter analyze` shows no issues)
- [ ] All tests passing (`flutter test`)
- [ ] Remove all debug print statements
- [ ] Remove any hardcoded test data
- [ ] Review and clean up TODO comments in codebase

### App Functionality

- [ ] EPUB import working correctly
- [ ] PDF import working correctly
- [ ] All TTS engines functioning (Kokoro, Piper, Supertonic)
- [ ] Voice download and management working
- [ ] Playback controls working (play, pause, skip, seek)
- [ ] System media controls working (lock screen, notification)
- [ ] Background audio playback working
- [ ] Bluetooth/headphone button controls working
- [ ] Progress saving and restoration working
- [ ] Settings persistence working

### Performance

- [ ] App startup time acceptable (< 3 seconds)
- [ ] TTS synthesis performance optimized
- [ ] Memory usage profiled and optimized
- [ ] Battery usage acceptable for background playback

---

## App Configuration

### App Identity

- [x] Choose final app name: **Éist** (UI), **Éist: Ebook/PDF to Audiobook** (App Store)
- [ ] Choose app bundle/package ID:
  - Android: `com.yourcompany.eist`
  - iOS: `com.yourcompany.eist`
- [ ] Create app icon (1024x1024px master, export all sizes)
- [ ] Create splash screen assets

### Update App Configuration Files

#### Android (`android/app/build.gradle`)

- [ ] Update `applicationId` to production package name
- [ ] Set `versionCode` (integer, increment with each release)
- [ ] Set `versionName` (e.g., "1.0.0")
- [ ] Set `minSdkVersion` (minimum 21 for audio_service)
- [ ] Set `targetSdkVersion` (34 or latest)

#### iOS (`ios/Runner/Info.plist`)

- [ ] Update `CFBundleIdentifier`
- [ ] Update `CFBundleVersion` and `CFBundleShortVersionString`
- [ ] Add `UIBackgroundModes` for audio
- [ ] Add privacy usage descriptions (microphone if needed)

#### Flutter (`pubspec.yaml`)

- [ ] Update `version` field (e.g., "1.0.0+1")
- [ ] Update `description`
- [ ] Review and clean up dependencies

### App Icons

- [ ] Generate Android icons (use flutter_launcher_icons or manual)
  - [ ] `mipmap-mdpi` (48x48)
  - [ ] `mipmap-hdpi` (72x72)
  - [ ] `mipmap-xhdpi` (96x96)
  - [ ] `mipmap-xxhdpi` (144x144)
  - [ ] `mipmap-xxxhdpi` (192x192)
  - [ ] Adaptive icon (foreground + background)
- [ ] Generate iOS icons (all required sizes)
  - [ ] 1024x1024 (App Store)
  - [ ] 180x180 (iPhone @3x)
  - [ ] 120x120 (iPhone @2x)
  - [ ] 167x167 (iPad Pro)
  - [ ] 152x152 (iPad @2x)
  - [ ] 76x76 (iPad @1x)

### Splash Screen

- [ ] Android splash screen configured (12-style if targeting Android 12+)
- [ ] iOS splash screen configured (LaunchScreen.storyboard)

---

## Android Deployment

### Developer Account

- [ ] Google Play Developer account created ($25 one-time fee)
- [ ] Account identity verified
- [ ] Developer profile completed

### App Signing

- [ ] Create production keystore:
  ```bash
  keytool -genkey -v -keystore ~/audiobook-release.keystore \
    -alias audiobook -keyalg RSA -keysize 2048 -validity 10000
  ```
- [ ] Store keystore password securely (password manager)
- [ ] Create `android/key.properties` (DO NOT commit to git):
  ```properties
  storePassword=<password>
  keyPassword=<password>
  keyAlias=audiobook
  storeFile=/path/to/audiobook-release.keystore
  ```
- [ ] Configure signing in `android/app/build.gradle`
- [ ] Enroll in Google Play App Signing (recommended)

### Build Release APK/AAB

- [ ] Clean build environment:
  ```bash
  flutter clean
  flutter pub get
  ```
- [ ] Build release AAB (preferred for Play Store):
  ```bash
  flutter build appbundle --release
  ```
- [ ] Build release APK (for testing):
  ```bash
  flutter build apk --release
  ```
- [ ] Test release build on physical device
- [ ] Test release build on multiple device sizes

### Google Play Console Setup

- [ ] Create new app in Play Console
- [ ] Complete app content questionnaire
- [ ] Set up store listing (see Marketing section)
- [ ] Configure pricing and distribution
- [ ] Set content rating (complete questionnaire)
- [ ] Set up data safety section:
  - [ ] What data does the app collect?
  - [ ] Is data encrypted in transit?
  - [ ] Can users request data deletion?
- [ ] Configure target audience and content

### Android-Specific Features

- [ ] Foreground service notification configured properly
- [ ] Request POST_NOTIFICATIONS permission for Android 13+
- [ ] Handle notification permission denial gracefully
- [ ] Android Auto support (optional)

---

## iOS Deployment

### Developer Account

- [ ] Apple Developer Program enrolled ($99/year)
- [ ] Development and distribution certificates created
- [ ] Provisioning profiles configured

### Xcode Configuration

- [ ] Open `ios/Runner.xcworkspace` in Xcode
- [ ] Set correct Bundle Identifier
- [ ] Configure signing team
- [ ] Set minimum iOS deployment target (iOS 12.0+)
- [ ] Enable required capabilities:
  - [ ] Background Modes > Audio
  - [ ] Associated Domains (if using universal links)

### App Store Connect Setup

- [ ] Create new app in App Store Connect
- [ ] Set up app information
- [ ] Configure pricing and availability
- [ ] Set age rating (complete questionnaire)
- [ ] Configure App Privacy:
  - [ ] Data types collected
  - [ ] Data usage purposes
  - [ ] Data linked to user identity

### Build & Archive

- [ ] Clean build:
  ```bash
  flutter clean
  flutter pub get
  cd ios && pod install && cd ..
  ```
- [ ] Build iOS release:
  ```bash
  flutter build ios --release
  ```
- [ ] Open in Xcode and Archive
- [ ] Upload to App Store Connect
- [ ] Test via TestFlight

### iOS-Specific Features

- [ ] Control Center integration working
- [ ] Lock screen controls working
- [ ] CarPlay support (optional)
- [ ] Background audio continues when app backgrounded
- [ ] Handle audio interruptions (phone calls, etc.)

---

## Monetization Implementation

### Strategy Selection

Choose monetization approach:
- [ ] **Freemium**: Free with premium features
- [ ] **Subscription**: Monthly/yearly access
- [ ] **One-time purchase**: Single payment for full app
- [ ] **Ad-supported**: Free with ads, pay to remove

### Recommended: Freemium + Subscription

#### Free Tier Features
- [ ] EPUB/PDF import (limited to X books)
- [ ] Basic TTS voice (Piper only)
- [ ] Standard playback controls
- [ ] Limited chapters per day

#### Premium Features (Subscription)
- [ ] Unlimited books
- [ ] All TTS voices (Kokoro, Supertonic)
- [ ] Offline playback
- [ ] Cloud sync/backup
- [ ] Advanced playback settings
- [ ] No daily limits

### Implementation Tasks

#### In-App Purchases Setup

**Android (Google Play)**
- [ ] Set up merchant account in Play Console
- [ ] Create subscription products:
  - [ ] Monthly subscription ($X.99/month)
  - [ ] Yearly subscription ($XX.99/year - ~20% discount)
- [ ] Set up grace period and account hold
- [ ] Configure trial period (7 days recommended)

**iOS (App Store)**
- [ ] Set up paid apps agreement in App Store Connect
- [ ] Create subscription products:
  - [ ] Monthly subscription
  - [ ] Yearly subscription
- [ ] Configure subscription group
- [ ] Set up promotional offers (optional)
- [ ] Configure free trial

#### Code Implementation

- [ ] Add `in_app_purchase` or `purchases_flutter` (RevenueCat) package
- [ ] Implement purchase flow:
  - [ ] Display subscription options
  - [ ] Handle purchase requests
  - [ ] Verify receipts (server-side recommended)
  - [ ] Restore purchases
- [ ] Implement entitlement checks:
  - [ ] Check subscription status on app launch
  - [ ] Gate premium features appropriately
  - [ ] Handle subscription expiration
- [ ] Implement subscription management UI:
  - [ ] Show current subscription status
  - [ ] Manage subscription button (links to store)
  - [ ] Restore purchases button

#### RevenueCat Integration (Recommended)

RevenueCat simplifies cross-platform subscription management:

- [ ] Create RevenueCat account
- [ ] Set up project in RevenueCat dashboard
- [ ] Connect Google Play and App Store
- [ ] Configure entitlements and offerings
- [ ] Add `purchases_flutter` package
- [ ] Initialize RevenueCat SDK
- [ ] Implement purchase flows using RevenueCat API

### Subscription Screens

- [ ] Create onboarding paywall screen
- [ ] Create settings subscription management screen
- [ ] Add "Pro" badge/indicator for premium features
- [ ] Create feature comparison table
- [ ] Add promotional banners for upgrades

### Testing Purchases

**Android**
- [ ] Set up license testing in Play Console
- [ ] Test purchase flow in test mode
- [ ] Test subscription renewal
- [ ] Test cancellation and restoration

**iOS**
- [ ] Set up sandbox testers in App Store Connect
- [ ] Test purchase flow in sandbox
- [ ] Test subscription renewal (accelerated)
- [ ] Test restoration

---

## Marketing & Store Listings

### App Description

- [ ] Write compelling app title (30 chars max)
- [ ] Write short description (80 chars max)
- [ ] Write full description (4000 chars max):
  - What the app does
  - Key features
  - Benefits to users
  - Call to action
- [ ] Research and add relevant keywords
- [ ] Write "What's New" for updates

### Screenshots

- [ ] Phone screenshots (minimum 2, recommended 5-8):
  - [ ] Library screen with books
  - [ ] Playback screen
  - [ ] Chapter selection
  - [ ] Voice settings
  - [ ] Lock screen controls
- [ ] Tablet screenshots (if supporting tablets)
- [ ] Consider adding device frames
- [ ] Add text overlays explaining features

### Video (Optional but Recommended)

- [ ] Create 15-30 second promo video
- [ ] Show key features and user experience
- [ ] Add captions (required for some regions)

### Store Assets

**Android**
- [ ] Feature graphic (1024x500px)
- [ ] Phone screenshots (minimum 2)
- [ ] 7-inch tablet screenshots (if applicable)
- [ ] 10-inch tablet screenshots (if applicable)
- [ ] Promo video (YouTube link)

**iOS**
- [ ] 6.5" display screenshots (iPhone 14 Pro Max)
- [ ] 5.5" display screenshots (iPhone 8 Plus)
- [ ] iPad Pro (12.9") screenshots (if supporting iPad)
- [ ] App Preview video (optional)

### Localization (Optional)

- [ ] Translate app description to key markets
- [ ] Create localized screenshots
- [ ] Consider hiring translators for quality

---

## Final Testing

### Functional Testing

- [ ] Complete app flow testing on release build
- [ ] Test on multiple Android devices/versions
- [ ] Test on multiple iOS devices/versions
- [ ] Test with no network connection
- [ ] Test with poor network connection
- [ ] Test background/foreground transitions
- [ ] Test device rotation (if supported)
- [ ] Test after force-killing app

### Compatibility Testing

**Android**
- [ ] Test on Android 8.0 (API 26)
- [ ] Test on Android 10 (API 29)
- [ ] Test on Android 12 (API 31)
- [ ] Test on Android 13/14 (latest)
- [ ] Test on Samsung devices
- [ ] Test on Pixel devices
- [ ] Test on budget devices

**iOS**
- [ ] Test on iOS 12 (if supporting)
- [ ] Test on iOS 15
- [ ] Test on iOS 17 (latest)
- [ ] Test on iPhone SE (small screen)
- [ ] Test on iPhone 14 Pro Max (large screen)
- [ ] Test on iPad (if supporting)

### Performance Testing

- [ ] Profile app startup time
- [ ] Profile memory usage during playback
- [ ] Test 4+ hour playback sessions
- [ ] Test with large library (50+ books)
- [ ] Monitor battery usage

### Accessibility Testing

- [ ] Test with TalkBack (Android)
- [ ] Test with VoiceOver (iOS)
- [ ] Verify content descriptions on all buttons
- [ ] Test with increased text size
- [ ] Verify color contrast meets WCAG guidelines

### Beta Testing

- [ ] Set up internal testing track (Google Play)
- [ ] Set up TestFlight (iOS)
- [ ] Recruit beta testers (friends, family, online communities)
- [ ] Collect and address feedback
- [ ] Fix critical bugs before public release

---

## Submission

### Pre-Submission Checklist

- [ ] All testing completed
- [ ] All store listing content ready
- [ ] Privacy policy URL available
- [ ] Terms of service URL available (if applicable)
- [ ] Support email configured
- [ ] Marketing website ready (optional)

### Android Submission

- [ ] Upload AAB to production track
- [ ] Complete release notes
- [ ] Submit for review
- [ ] Monitor review status
- [ ] Address any policy violations

### iOS Submission

- [ ] Upload build via Xcode or Transporter
- [ ] Complete App Store listing
- [ ] Submit for review
- [ ] Respond to App Review team promptly
- [ ] Address any rejection reasons

### Expected Review Times

- **Google Play**: Usually 1-3 days, can be up to 7 days for first app
- **App Store**: Usually 24-48 hours, can be 3-7 days

---

## Post-Launch

### Monitor & Respond

- [ ] Monitor crash reports (Firebase Crashlytics recommended)
- [ ] Monitor user reviews
- [ ] Respond to negative reviews constructively
- [ ] Track analytics (downloads, retention, engagement)
- [ ] Monitor subscription metrics (if applicable)

### Iterate

- [ ] Prioritize bug fixes based on crash reports
- [ ] Collect feature requests from reviews
- [ ] Plan regular update schedule
- [ ] Keep dependencies updated
- [ ] Stay current with OS changes

### Marketing

- [ ] Share on social media
- [ ] Submit to app review websites
- [ ] Consider ASO (App Store Optimization)
- [ ] Explore paid user acquisition (if budget allows)
- [ ] Engage with audiobook communities

---

## Timeline Estimate

| Phase | Estimated Time |
|-------|---------------|
| Pre-deployment checklist | 1-2 days |
| App configuration | 1 day |
| Monetization implementation | 2-3 days |
| Store listings & assets | 2-3 days |
| Final testing | 2-3 days |
| Beta testing | 1-2 weeks |
| Review & revisions | 1-2 days |
| **Total** | **2-3 weeks** |

---

## Resources

### Documentation

- [Flutter Deployment Docs](https://docs.flutter.dev/deployment)
- [Google Play Console Help](https://support.google.com/googleplay/android-developer)
- [App Store Connect Help](https://developer.apple.com/help/app-store-connect/)
- [RevenueCat Docs](https://www.revenuecat.com/docs)

### Tools

- `flutter_launcher_icons` - App icon generation
- `flutter_native_splash` - Splash screen generation
- `purchases_flutter` - RevenueCat SDK for subscriptions
- Firebase Crashlytics - Crash reporting
- Firebase Analytics - Usage analytics

---

*Last updated: January 2025*
