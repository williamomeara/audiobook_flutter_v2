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

## Tech Stack: v0.dev + Vercel (Recommended)

**Why v0.dev:**
- AI generates professional React/Tailwind code from prompts
- Iterative refinement ("make the hero bigger", "add dark mode")
- Export directly to Next.js project
- Deploy to Vercel with one click

---

## Step-by-Step: Build with v0.dev

### Step 1: Generate Landing Page

1. Go to **[v0.dev](https://v0.dev)** and sign in with GitHub
2. Use this prompt as a starting point:

```
Create a landing page for Eist, an AI-powered audiobook app.

Design requirements:
- Dark mode design with slate-900 (#0F172A) background
- Amber (#F59E0B) accent color for CTAs and highlights
- Clean, modern typography using Inter font

Sections needed:
1. Hero: Large headline "Eist. Listen to any book." with subheadline 
   "AI-powered audiobook reader that transforms any EPUB or PDF into 
   natural-sounding audio". Two CTA buttons: "Download for Android" and 
   "Download for iOS". Phone mockup on the right.

2. Features: 4-column grid showing:
   - AI Text-to-Speech (multiple voice engines)
   - Read Any Book (EPUB & PDF support)
   - Playback Controls (speed, sleep timer)
   - Works Offline (after voice download)

3. How It Works: 3-step process
   - Import your book
   - Choose a voice
   - Start listening

4. Download CTA: Final call to action with app store buttons

5. Footer: Links to Privacy Policy, Terms, and social links

Style: Professional, minimal, tech-forward like Linear or Raycast
```

3. **Iterate** on the result:
   - "Make the hero section taller with more padding"
   - "Add a subtle gradient to the background"
   - "Make the feature icons amber colored"
   - "Add an app screenshot mockup"

### Step 2: Export to Code

1. Click **"Code"** button in v0.dev
2. Choose **"Next.js"** export
3. Copy the component code or click **"Deploy to Vercel"**

### Step 3: Set Up Repository

```bash
# Option A: Deploy directly from v0.dev
# Click "Deploy to Vercel" - it creates a repo and deploys automatically

# Option B: Manual setup
npx create-next-app@latest eist-landing
cd eist-landing

# Copy v0-generated components into src/app/page.tsx
# Install dependencies if needed (e.g., lucide-react for icons)
npm install lucide-react

# Run locally
npm run dev
```

### Step 4: Add Custom Domain

1. Go to **Vercel Dashboard** → Your Project → **Settings** → **Domains**
2. Add `eist.app`
3. In **Namecheap**, add DNS records:

| Type | Host | Value |
|------|------|-------|
| A | @ | `76.76.21.21` |
| CNAME | www | `cname.vercel-dns.com` |

4. Wait 5-10 minutes for DNS propagation
5. Vercel auto-provisions HTTPS

### Step 5: Add Content Pages

Generate additional pages in v0.dev:

**Privacy Policy prompt:**
```
Create a privacy policy page for Eist app. Same dark theme (slate-900 
background, amber accents). Include sections for: data collection, 
usage, storage, third-party services, user rights. Professional but 
readable format.
```

**Terms of Service prompt:**
```
Create a terms of service page for Eist app. Same dark theme. 
Standard app terms covering: usage license, restrictions, disclaimers, 
liability limitations.
```

---

## v0.dev Tips

| Tip | Why |
|-----|-----|
| Be specific about colors | Prevents AI from using defaults |
| Reference other sites | "Like Linear's homepage" helps with style |
| Iterate in small steps | "Change X" is better than regenerating |
| Use "Code" view often | Check generated code quality |
| Export early | Don't over-iterate in v0 before testing real code |

---

## Alternative Tech Stack Options

### Option A: Static HTML/CSS (Simplest)
```
Pros: No build step, instant deploy to GitHub Pages
Cons: No components, harder to maintain
Best for: Quick MVP, < 5 pages
```

### Option B: Astro
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

## Action Plan (v0.dev Workflow)

### Phase 1: Generate & Iterate (Day 1)
- [ ] Go to v0.dev and generate landing page with prompt above
- [ ] Iterate on design (3-5 refinement prompts)
- [ ] Generate Privacy Policy page
- [ ] Generate Terms of Service page

### Phase 2: Deploy (Day 1-2)
- [ ] Click "Deploy to Vercel" from v0.dev
- [ ] Add eist.app domain in Vercel settings
- [ ] Configure DNS in Namecheap
- [ ] Verify HTTPS is working

### Phase 3: Content & Assets (Day 2-3)
- [ ] Take app screenshots (3-5 screens)
- [ ] Create phone mockup in Figma (optional)
- [ ] Add actual App Store / Play Store links
- [ ] Review and finalize copy

### Phase 4: Polish (Day 3-4)
- [ ] Test on mobile devices
- [ ] Check page speed (Lighthouse)
- [ ] Add meta tags for SEO
- [ ] Add favicon and Open Graph image
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
