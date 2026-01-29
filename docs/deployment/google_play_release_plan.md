# Google Play Store Release Plan with Freemium Monetization

**Based on:** [docs/monetization/freemium_model.md](../monetization/freemium_model.md)
**Last Updated:** January 29, 2026

---

## Table of Contents

1. [Pre-Release Preparation](#1-pre-release-preparation)
2. [Google Play Developer Account Setup](#2-google-play-developer-account-setup)
3. [App Configuration](#3-app-configuration)
4. [In-App Billing Setup](#4-in-app-billing-setup)
5. [RevenueCat Integration](#5-revenuecat-integration)
6. [Store Listing Preparation](#6-store-listing-preparation)
7. [Testing & QA](#7-testing--qa)
8. [Staged Rollout](#8-staged-rollout)
9. [Post-Launch Tasks](#9-post-launch-tasks)

---

## 1. Pre-Release Preparation

### 1.1 Code Preparation Checklist

- [ ] **Remove debug code**
  ```bash
  # Check for print statements
  grep -r "print(" lib/ | grep -v ".dart:.*print"
  
  # Ensure release mode builds work
  flutter build appbundle --release
  ```

- [ ] **Update version number**
  ```yaml
  # pubspec.yaml
  version: 1.0.0+1  # Format: major.minor.patch+build
  ```

- [ ] **Configure ProGuard/R8 (Android)**
  - File: `android/app/build.gradle.kts`
  - Enable minification for release builds

- [ ] **Set up signing keys**
  ```bash
  # Create upload keystore (SAVE THIS SECURELY!)
  keytool -genkey -v -keystore ~/audiobook-upload-key.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
  ```

### 1.2 Privacy Policy & Terms

- [ ] **Create Privacy Policy** (required for Play Store)
  - Host at: `https://yourwebsite.com/privacy-policy`
  - Must cover: data collection, TTS processing, local storage, analytics
  - Template resources: [Privacy Policy Generator](https://www.termsfeed.com/privacy-policy-generator/)

- [ ] **Create Terms of Service**
  - Host at: `https://yourwebsite.com/terms`
  - Cover: subscription terms, refund policy, content rights

### 1.3 Required Assets

| Asset | Dimensions | Format | Purpose |
|-------|------------|--------|---------|
| App Icon | 512x512 | PNG | Store listing |
| Feature Graphic | 1024x500 | PNG/JPEG | Store header |
| Screenshots | 16:9 or 9:16 | PNG/JPEG | Min 2, max 8 per device type |
| Phone Screenshots | 1080x1920+ | PNG | Required |
| Tablet Screenshots | 1920x1080+ | PNG | Recommended |
| Promotional Video | 30-120s | YouTube link | Optional but recommended |

---

## 2. Google Play Developer Account Setup

### 2.1 Create Developer Account

1. **Go to:** [Google Play Console](https://play.google.com/console)
2. **Pay:** $25 one-time registration fee
3. **Complete:** Identity verification (takes 2-7 days)
4. **Provide:** Business contact information

### 2.2 Configure Merchant Account (Required for Monetization)

1. **Navigate:** Play Console → Setup → Payments profile
2. **Link or create:** Google Payments merchant account
3. **Provide:**
   - Business/personal details
   - Tax information (W-9 for US, W-8BEN for international)
   - Bank account for payouts
4. **Wait:** Account verification (2-3 business days)

### 2.3 Configure Testing Tracks

```
Internal Testing → Closed Testing → Open Testing → Production
```

Create test tracks for:
- [ ] **Internal testing** (immediate distribution, up to 100 testers)
- [ ] **Closed testing** (up to 1000 testers via email list)
- [ ] **Open testing** (unlimited, public access)

---

## 3. App Configuration

### 3.1 Android Manifest Updates

```xml
<!-- android/app/src/main/AndroidManifest.xml -->
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    
    <!-- Required permissions -->
    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK"/>
    <uses-permission android:name="com.android.vending.BILLING"/>
    
    <application
        android:label="Audiobook Reader"
        android:icon="@mipmap/ic_launcher"
        android:name="${applicationName}"
        android:allowBackup="true">
        
        <!-- ... activities ... -->
        
    </application>
</manifest>
```

### 3.2 Build Configuration

```kotlin
// android/app/build.gradle.kts
android {
    namespace = "com.yourcompany.audiobook_reader"
    
    defaultConfig {
        applicationId = "com.yourcompany.audiobook_reader"
        minSdk = 24
        targetSdk = 34
        versionCode = 1
        versionName = "1.0.0"
    }
    
    signingConfigs {
        create("release") {
            storeFile = file(System.getenv("KEYSTORE_PATH") ?: "upload-keystore.jks")
            storePassword = System.getenv("KEYSTORE_PASSWORD")
            keyAlias = System.getenv("KEY_ALIAS")
            keyPassword = System.getenv("KEY_PASSWORD")
        }
    }
    
    buildTypes {
        getByName("release") {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            signingConfig = signingConfigs.getByName("release")
        }
    }
    
    bundle {
        language {
            enableSplit = true
        }
        density {
            enableSplit = true
        }
        abi {
            enableSplit = true
        }
    }
}
```

### 3.3 Create Signing Key

```bash
# Generate upload keystore
keytool -genkey -v \
  -keystore ~/audiobook-upload-key.jks \
  -keyalg RSA \
  -keysize 2048 \
  -validity 10000 \
  -alias upload \
  -dname "CN=Your Name, OU=Your Unit, O=Your Company, L=City, ST=State, C=US"

# Store password securely (use password manager)
# NEVER commit the keystore or passwords to git!

# Create key.properties (add to .gitignore)
cat > android/key.properties << EOF
storePassword=your_store_password
keyPassword=your_key_password
keyAlias=upload
storeFile=/path/to/audiobook-upload-key.jks
EOF
```

---

## 4. In-App Billing Setup

### 4.1 Create Subscription Products in Play Console

1. **Navigate:** Play Console → Your App → Monetize → Products → Subscriptions
2. **Create subscription:**

**Monthly Subscription:**
```
Product ID: premium_monthly
Name: Premium Monthly
Description: Unlimited books, all voices, pre-synthesis, and more
Price: $5.00 USD
Billing period: Monthly
Grace period: 7 days
Free trial: 3 months (90 days)
```

**Annual Subscription:**
```
Product ID: premium_annual
Name: Premium Annual
Description: Unlimited books, all voices, pre-synthesis, and more (save $10!)
Price: $50.00 USD
Billing period: Yearly
Grace period: 14 days
Free trial: 3 months (90 days)
```

### 4.2 Configure Regional Pricing

1. Go to subscription → Pricing tab
2. Click "Add regional pricing"
3. Configure for key markets:
   - **India:** ₹199/month (70% discount)
   - **Brazil:** R$14.90/month (50% discount)
   - **Indonesia:** Rp29,000/month (70% discount)
   - **Mexico:** MX$59/month (50% discount)

### 4.3 Add Billing Library to App

```yaml
# pubspec.yaml
dependencies:
  purchases_flutter: ^8.1.0  # RevenueCat SDK (recommended)
  # OR
  in_app_purchase: ^3.2.0    # Official Flutter plugin
```

---

## 5. RevenueCat Integration

### 5.1 Why RevenueCat?

- Handles receipt validation automatically
- Works across iOS and Android
- Provides analytics dashboard
- Simplifies subscription management
- Free tier for <$2.5K MTR

### 5.2 Setup RevenueCat Account

1. **Sign up:** [RevenueCat Dashboard](https://app.revenuecat.com)
2. **Create project:** "Audiobook Reader"
3. **Add Android app:**
   - Package name: `com.yourcompany.audiobook_reader`
   - Service account JSON: (from Google Cloud Console)

### 5.3 Configure Service Account for Google Play

1. **Google Cloud Console:**
   - Create service account
   - Grant "Pub/Sub Admin" and "Monitoring Viewer" roles
   - Generate JSON key file

2. **Play Console:**
   - Settings → API access → Link Google Cloud project
   - Grant "View financial data" to service account

3. **RevenueCat:**
   - Upload service account JSON
   - Configure products to match Play Console

### 5.4 Implement in Flutter

```dart
// lib/app/subscription/subscription_service.dart
import 'package:purchases_flutter/purchases_flutter.dart';

class SubscriptionService {
  static const String _revenueCatApiKey = 'your_revenuecat_public_api_key';
  
  Future<void> initialize() async {
    await Purchases.configure(
      PurchasesConfiguration(_revenueCatApiKey)
        ..appUserID = null  // Anonymous user (no account required)
    );
  }
  
  Future<bool> isPremium() async {
    final customerInfo = await Purchases.getCustomerInfo();
    return customerInfo.entitlements.active.containsKey('premium');
  }
  
  Future<void> purchaseMonthly() async {
    final offerings = await Purchases.getOfferings();
    final package = offerings.current?.monthly;
    if (package != null) {
      await Purchases.purchasePackage(package);
    }
  }
  
  Future<void> purchaseAnnual() async {
    final offerings = await Purchases.getOfferings();
    final package = offerings.current?.annual;
    if (package != null) {
      await Purchases.purchasePackage(package);
    }
  }
  
  Future<void> restorePurchases() async {
    await Purchases.restorePurchases();
  }
}
```

### 5.5 Configure Entitlements

In RevenueCat Dashboard:
1. **Create Entitlement:** "premium"
2. **Attach Products:**
   - `premium_monthly`
   - `premium_annual`

---

## 6. Store Listing Preparation

### 6.1 App Details

**Title:** (30 characters max)
```
Audiobook Reader - AI TTS
```

**Short Description:** (80 characters max)
```
Turn any book into an audiobook with AI voices. Read unlimited hours for free!
```

**Full Description:** (4000 characters max)
```markdown
📚 Turn Any Book Into an Audiobook

Audiobook Reader uses cutting-edge AI text-to-speech to transform your EPUB and PDF books into professionally narrated audiobooks - completely free!

🎧 UNLIMITED FREE READING
• Read as many hours as you want
• No daily limits or caps
• Full audiobook experience with chapters and bookmarks

📖 WORKS WITH YOUR BOOKS
• Import EPUB and PDF files
• Automatic chapter detection
• Beautiful reading interface

🔊 PREMIUM AI VOICES
• Natural-sounding speech synthesis
• Multiple voice options
• Adjustable speed and pitch

⭐ FREE FEATURES
✓ Unlimited listening hours
✓ Background playback
✓ Sleep timer
✓ Speed control (0.5x - 2x)
✓ Bookmarks
✓ Chapter navigation
✓ Offline mode

💎 PREMIUM ($5/month after 3 months free)
✓ Unlimited books in library
✓ 20+ premium voices
✓ Pre-synthesis for instant playback
✓ Unlimited cache storage
✓ Priority processing

🆓 TRY PREMIUM FREE FOR 3 MONTHS
Start your free trial today - no credit card required. Your premium subscription will only begin after 3 months, and you can cancel anytime.

📱 SIMPLE AND ELEGANT
Beautiful, ad-free interface designed for focused reading. No account required - just download and start listening.

🔒 PRIVACY FIRST
Your books stay on your device. No cloud storage, no tracking, no data collection.

Questions? Contact us at support@yourapp.com
```

### 6.2 Category & Tags

- **Category:** Books & Reference
- **Content Rating:** Everyone
- **Tags:** audiobooks, text-to-speech, ebook reader, AI voice, audiobook maker

### 6.3 Screenshots Required

Prepare screenshots showing:
1. Library view with imported books
2. Book details / chapter list
3. Playback screen with controls
4. Voice selection (premium feature preview)
5. Settings / customization options

### 6.4 Content Rating Questionnaire

Complete the IARC rating questionnaire:
- No violence
- No sexual content
- No controlled substances
- User-generated content: No (users import their own books)
- In-app purchases: Yes

Expected rating: **Everyone**

---

## 7. Testing & QA

### 7.1 Internal Testing Setup

1. **Create release track:**
   ```bash
   flutter build appbundle --release
   # Output: build/app/outputs/bundle/release/app-release.aab
   ```

2. **Upload to internal testing:**
   - Play Console → Testing → Internal testing
   - Create release → Upload AAB
   - Add test email addresses

### 7.2 License Testers

1. **Add testers:** Play Console → Settings → License testing
2. **Add emails:** All test users who need to test purchases
3. **Benefit:** Test subscriptions without real charges

### 7.3 Test Scenarios

- [ ] Fresh install and onboarding
- [ ] Book import (EPUB and PDF)
- [ ] Free tier functionality (1 book limit, 3 voices)
- [ ] Paywall display when hitting limits
- [ ] Subscription purchase flow
- [ ] Premium feature unlock after purchase
- [ ] Subscription restore
- [ ] Offline functionality
- [ ] Background playback
- [ ] 3-month free trial flow

### 7.4 Pre-Launch Checklist

- [ ] All crash analytics integrated (Firebase Crashlytics)
- [ ] Analytics tracking subscription events
- [ ] Error handling for billing errors
- [ ] Graceful degradation if billing unavailable
- [ ] Testing on multiple devices (different Android versions)
- [ ] Battery optimization whitelisting prompt
- [ ] Large file handling (books over 10MB)

---

## 8. Staged Rollout

### 8.1 Rollout Strategy

**Week 1-2: Internal Testing**
- 10-20 internal testers
- Fix critical bugs
- Validate subscription flow

**Week 3-4: Closed Beta**
- 100-500 beta testers
- Collect feedback
- Monitor crash rates

**Week 5-6: Open Beta**
- Public opt-in testing
- A/B test paywall messaging
- Optimize conversion

**Week 7+: Production Release**
- 10% rollout initially
- Monitor metrics closely
- Increase to 100% if stable

### 8.2 Release Configuration

```
Play Console → Production → Create release
→ Staged rollout percentage: 10%
→ Increase gradually: 10% → 25% → 50% → 100%
```

### 8.3 Rollout Monitoring

Monitor these metrics during rollout:
- **Crash rate:** Should be < 1%
- **ANR rate:** Should be < 0.5%
- **User ratings:** Watch for negative reviews
- **Purchase errors:** Track billing failures

---

## 9. Post-Launch Tasks

### 9.1 Immediate (Week 1)

- [ ] Monitor Play Console vitals dashboard
- [ ] Respond to user reviews
- [ ] Track subscription conversions
- [ ] Fix any critical bugs

### 9.2 Short-term (Month 1)

- [ ] Analyze user behavior with analytics
- [ ] A/B test upgrade prompts
- [ ] Optimize paywall conversion
- [ ] Release bug fix updates

### 9.3 Ongoing

- [ ] Weekly review of metrics
- [ ] Monthly feature releases
- [ ] Quarterly pricing reviews
- [ ] Annual Play Store listing optimization

### 9.4 Key Metrics to Track

| Metric | Target | Tool |
|--------|--------|------|
| Daily Active Users | Growth | Firebase Analytics |
| Free-to-Paid Conversion | 15-20% | RevenueCat |
| Subscription Retention | 80%+ | RevenueCat |
| Crash-free Users | 99%+ | Crashlytics |
| Store Rating | 4.5+ | Play Console |
| Trial-to-Paid | 30%+ | RevenueCat |

---

## Quick Reference: Timeline

| Phase | Duration | Key Tasks |
|-------|----------|-----------|
| Pre-release | 1-2 weeks | Code prep, assets, accounts |
| Billing setup | 3-5 days | Products, RevenueCat, testing |
| Internal testing | 1-2 weeks | Bug fixes, validation |
| Closed beta | 2 weeks | User feedback, optimization |
| Open beta | 1-2 weeks | Final testing |
| Production | Ongoing | Gradual rollout, monitoring |

**Total time to production: 6-10 weeks**

---

## Files to Create/Update

```
audiobook_flutter_v2/
├── android/
│   ├── key.properties              # Signing config (gitignored)
│   ├── app/
│   │   ├── build.gradle.kts        # Update for release
│   │   └── src/main/
│   │       └── AndroidManifest.xml # Add billing permission
├── lib/
│   └── app/
│       └── subscription/
│           ├── subscription_service.dart
│           ├── premium_validator.dart
│           ├── feature_gate.dart
│           └── usage_tracker.dart
├── pubspec.yaml                    # Add RevenueCat dependency
└── docs/
    └── deployment/
        └── google_play_release_plan.md  # This file
```

---

## Resources

- [Google Play Console](https://play.google.com/console)
- [RevenueCat Documentation](https://docs.revenuecat.com)
- [Flutter In-App Purchase Guide](https://docs.flutter.dev/codelabs/in-app-purchases)
- [Play Billing Library](https://developer.android.com/google/play/billing)
- [App Store Optimization Guide](https://developer.android.com/distribute/best-practices/grow/app-store-optimization)
