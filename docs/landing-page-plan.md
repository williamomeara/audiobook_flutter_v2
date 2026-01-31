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

### Eist Color Palette (from app)

The app uses a dual-theme design. Use these exact values in Figma:

**Dark Mode (Primary Theme for Landing Page)**
| Token | Hex | Usage |
|-------|-----|-------|
| Background | `#0F172A` (slate-900) | Page background |
| Card/Surface | `#1E293B` (slate-800) | Cards, sections |
| Border | `#334155` (slate-700) | Borders, dividers |
| Text Primary | `#FFFFFF` | Headlines, body |
| Text Secondary | `#94A3B8` (slate-400) | Captions, labels |
| Accent | `#F59E0B` (amber-500) | CTAs, highlights |
| Accent Hover | `#FBBF24` (amber-400) | Hover states |
| Danger | `#EF4444` | Error states |

**Light Mode (Optional)**
| Token | Hex | Usage |
|-------|-----|-------|
| Background | `#F5F5F5` | Page background |
| Card/Surface | `#FFFFFF` | Cards |
| Text Primary | `#030213` | Headlines, body |
| Text Secondary | `#717182` | Captions |

### Typography

**Recommended Fonts (free, web-safe):**
- Headlines: **Inter** (bold, 700 weight)
- Body: **Inter** (regular, 400 weight)
- Fallback: System font stack

**Type Scale:**
| Element | Size | Weight |
|---------|------|--------|
| H1 (Hero) | 48-64px | Bold |
| H2 (Section) | 32-40px | Bold |
| H3 (Card title) | 24px | Semibold |
| Body | 16-18px | Regular |
| Caption | 14px | Regular |

---

## Figma Workflow

### Step 1: Set Up Figma Design System

Create a new Figma file with shared styles:

1. **Create color styles** matching the palette above
   - Right-click color → "Create style"
   - Name: `colors/background`, `colors/accent`, etc.

2. **Create text styles** for typography
   - H1, H2, H3, Body, Caption
   - Include line-height (1.2 for headers, 1.5 for body)

3. **Create components** for reusable elements
   - Button (primary, secondary, ghost)
   - Feature card
   - Phone mockup frame

### Step 2: Export Design to Code

**Option A: Figma Dev Mode (Recommended)**
- Enable Dev Mode in Figma
- View CSS values for each element
- Copy Tailwind classes or raw CSS

**Option B: Figma to Tailwind Plugin**
- Install "Figma to Code" or "Builder.io" plugin
- Export components as React/Tailwind code
- Clean up and integrate into Astro

**Option C: Manual Translation**
- Design in Figma
- Manually recreate in Astro using Tailwind
- Best for small sites where you want full control

### Step 3: Match App Theme in Tailwind

Create a `tailwind.config.mjs` with Eist colors:

```javascript
export default {
  theme: {
    extend: {
      colors: {
        // Dark mode (default)
        background: '#0F172A',
        surface: '#1E293B',
        border: '#334155',
        'text-primary': '#FFFFFF',
        'text-secondary': '#94A3B8',
        accent: '#F59E0B',
        'accent-hover': '#FBBF24',
        
        // Semantic
        eist: {
          slate: {
            700: '#334155',
            800: '#1E293B',
            900: '#0F172A',
          },
          amber: {
            400: '#FBBF24',
            500: '#F59E0B',
            600: '#D97706',
          }
        }
      },
      fontFamily: {
        sans: ['Inter', 'system-ui', 'sans-serif'],
      }
    }
  }
}
```

### Visual Assets Needed
- App icon (high-res PNG, 512x512+)
- App screenshots (3-5, phone frame mockups)
- Phone mockup template (use Figma's device frames)
- Feature icons (use Lucide or Phosphor icons)

---

## Deployment Options

| Platform | Cost | Setup | Custom Domain | Deploy Previews | Best For |
|----------|------|-------|---------------|-----------------|----------|
| **Vercel** | Free tier | Easiest | ✅ | ✅ Yes | ⭐ **Recommended** |
| **Netlify** | Free tier | Easy | ✅ | ✅ Yes | Alternative to Vercel |
| **Cloudflare Pages** | Free | Easy | ✅ | ✅ Yes | Edge performance |
| **GitHub Pages** | Free | Easy | ✅ | ❌ No | Simple static only |

### Recommendation: Vercel

**Why Vercel:**
- Zero-config Astro deployment (auto-detects framework)
- Automatic HTTPS with custom domain
- Deploy previews for every PR
- Global CDN (fast worldwide)
- Generous free tier (100GB bandwidth/month)
- Built by same team that created Next.js (Astro works great too)

### Setup with Vercel

```bash
# 1. Push repo to GitHub
git remote add origin https://github.com/USERNAME/eist-landing.git
git push -u origin main

# 2. Connect to Vercel
# Go to vercel.com → New Project → Import GitHub repo
# Vercel auto-detects Astro and configures build

# 3. Add custom domain
# Project Settings → Domains → Add "eist.app"
# Add DNS records in Namecheap:
#   Type: A, Host: @, Value: 76.76.21.21
#   Type: CNAME, Host: www, Value: cname.vercel-dns.com
```

### Alternative: Cloudflare Pages

If you want edge-optimized performance and already use Cloudflare:

```bash
# Similar process - connect GitHub repo
# Cloudflare Pages auto-detects Astro
# Custom domain setup in Cloudflare DNS (even simpler if domain is on Cloudflare)
```

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
