# Landing Page Plan for Eist

## Overview

A landing page to showcase and promote **Eist** — an AI-powered audiobook reader that transforms any EPUB or PDF into natural-sounding audio.

> *Eist* (pronounced "esht") is Irish for "listen"

---

## Domain

**Purchased:** `eist.app` from Namecheap

---

## Recommendation: Separate Repository

**Verdict: Create a new repository for the landing page**

### Why separate?

| Factor | In This Repo | Separate Repo |
|--------|--------------|---------------|
| **Deployment** | Conflicts with Flutter web build | Simple static hosting |
| **Build process** | Complicates CI/CD | Independent, fast builds |
| **Technology** | Constrained to Flutter | Freedom (React, Vue, plain HTML) |
| **Maintenance** | Couples two different concerns | Clean separation |
| **Team access** | Gives designers app code access | Isolate marketing site |

**Recommendation:** Create `eist-landing` repo with static site generator (Next.js, Astro, or plain HTML).

---

## Tech Stack Options

### Option A: Static HTML/CSS (Simplest)
```
Pros: No build step, instant deploy to GitHub Pages
Cons: No components, harder to maintain
Best for: Quick MVP, < 5 pages
```

### Option B: Astro (Recommended)
```
Pros: Fast builds, modern DX, partial hydration
Cons: Learning curve if unfamiliar
Best for: Static marketing site with some interactivity
```

### Option C: Next.js
```
Pros: React ecosystem, dynamic capabilities
Cons: Overkill for static landing page
Best for: If you need SSR or complex features
```

---

## Landing Page Structure

### Pages Needed

1. **Home** (`/`)
   - Hero section with app mockup
   - Key features grid (3-4 features)
   - Download CTA buttons (iOS/Android)
   - Testimonials/social proof (if available)
   
2. **Features** (`/features`)
   - Detailed feature breakdown
   - Screenshots/GIFs of app in action
   - AI TTS technology explanation

3. **Download** (`/download`) or link directly to stores
   - App Store link
   - Google Play link
   - System requirements

4. **Privacy Policy** (`/privacy`)
   - Required for app stores

5. **Terms of Service** (`/terms`)
   - Required for app stores

---

## Key Content Sections

### Hero Section
```
Headline: "Eist. Listen to any book."
Subheadline: "AI-powered audiobook reader that transforms any 
              EPUB or PDF into natural-sounding audio"
CTA: [Download for Android] [Download for iOS]
Visual: Phone mockup showing Eist app
```

### Features to Highlight

1. **AI Text-to-Speech**
   - Multiple engine options (Kokoro, Piper, Supertonic)
   - Natural-sounding voices
   - Offline capability after model download

2. **Read Any Book**
   - EPUB support
   - PDF support
   - Import from device

3. **Playback Control**
   - Variable speed
   - Sleep timer
   - Background playback
   - Chapter navigation

4. **Smart Caching**
   - Pre-synthesizes upcoming content
   - Saves battery
   - Works offline

---

## Design Direction

### Colors (from app)
- Primary: App's accent color
- Background: Dark mode friendly
- Text: High contrast for readability

### Typography
- Headlines: Bold, modern sans-serif
- Body: Clean, readable

### Visual Assets Needed
- App icon (high-res)
- App screenshots (3-5)
- Phone mockup templates
- Feature icons

---

## Deployment Options

| Platform | Cost | Setup | Custom Domain |
|----------|------|-------|---------------|
| **GitHub Pages** | Free | Easy | ✅ |
| **Vercel** | Free tier | Easy | ✅ |
| **Netlify** | Free tier | Easy | ✅ |
| **Cloudflare Pages** | Free | Easy | ✅ |

**Recommendation:** Vercel or Netlify for easy deploy previews and HTTPS.

---

## Action Plan

### Phase 1: Setup (Day 1)
- [ ] Create new GitHub repo `eist-landing`
- [ ] Initialize with Astro or HTML template
- [ ] Configure deployment to Vercel/Netlify
- [ ] Set up custom domain (if available)

### Phase 2: Content (Day 2-3)
- [ ] Write copy for all sections
- [ ] Create/gather app screenshots
- [ ] Design hero mockup
- [ ] Write privacy policy
- [ ] Write terms of service

### Phase 3: Build (Day 3-5)
- [ ] Build home page
- [ ] Build features page
- [ ] Add download links
- [ ] Add privacy/terms pages
- [ ] Mobile responsive testing

### Phase 4: Polish (Day 5-7)
- [ ] SEO optimization
- [ ] Performance optimization
- [ ] Cross-browser testing
- [ ] Analytics setup (Plausible, Fathom, or GA)

---

## Quick Start: Astro

If going with Astro:

```bash
# Create new landing page repo
mkdir eist-landing && cd eist-landing

# Initialize Astro
npm create astro@latest

# Use starter template (pick minimal or landing page template)
# Add Tailwind for styling
npx astro add tailwind

# Run locally
npm run dev

# Deploy to Vercel
npm i -g vercel
vercel
```

---

## Quick Start: Static HTML

If going with plain HTML:

```bash
# Create new repo
mkdir eist-landing && cd eist-landing
git init

# Create structure
mkdir -p css js images
touch index.html css/style.css

# Use GitHub Pages for hosting
# Enable in repo Settings > Pages > Source: main branch
```

---

## Next Steps

1. ~~**Decision needed:** Which tech stack?~~ → Astro recommended
2. ~~**Decision needed:** Domain name?~~ → **eist.app** (purchased from Namecheap)
3. **Assets needed:** App screenshots, icon, mockups
4. **Content needed:** Feature descriptions, privacy policy

Once decided, I can help scaffold the landing page in a new repository or start with a basic template here for prototyping.
