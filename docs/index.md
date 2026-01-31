# Audiobook Flutter V2 - Documentation Index

Welcome to the Audiobook Flutter V2 documentation. This guide will help you understand the codebase, set up development, and navigate the project.

## Quick Links

- **[Getting Started](./getting-started/)** - Setup, installation, and running the app
- **[Architecture](./architecture/)** - System design, state machines, and deep dives (source of truth)
- **[Features](./features/)** - In-progress feature documentation
- **[Completed Features](./features/completed/)** - Finished feature implementations
- **[API Reference](./api-reference/)** - API and provider documentation
- **[Guides](./guides/)** - How-to guides for common tasks
- **[Modules](./modules/)** - Package documentation
- **[Decisions](./decisions/)** - Architecture decisions (ADRs)
- **[Archive](./archive/)** - Historical documentation and completed work

## Documentation Structure

```
docs/
├── index.md                          # This file
├── COPILOT_POLICY.md                # AI assistant guidelines
│
├── architecture/                    # 📐 ARCHITECTURE - Source of Truth
│   ├── ARCHITECTURE.md             # System design overview
│   ├── CACHE_ARCHITECTURE_PLAN.md  # Cache system design
│   ├── audio_synthesis_pipeline_state_machine.md
│   ├── playback_screen_state_machine.md
│   ├── sleep_timer_state_machine.md
│   ├── tts_synthesis_state_machine.md
│   ├── smart-synthesis/            # Smart synthesis system
│   └── improvements/               # Audits and optimization plans
│
├── getting-started/                 # Project setup & onboarding
│   ├── setup.md                     # Development environment setup
│   └── INSTALLATION_GUIDE.md        # Installation instructions
│
├── guides/                          # How-to guides
│   ├── adding-new-features.md       # Feature development workflow
│   ├── MANUAL_TESTING_GUIDE.md      # Testing procedures
│   └── COMPRESSION_BEHAVIOR_GUIDE.md # Audio compression
│
├── api-reference/                   # Provider & API docs
│   └── DOWNLOAD_URLS_REFERENCE.md   # Resource download URLs
│
├── features/                        # Feature documentation
│   ├── FEATURE_TEMPLATE.md          # Template for new features
│   ├── completed/                   # ✅ Completed features
│   │   ├── TTS_IMPLEMENTATION_COMPLETE.md
│   │   ├── IMPLEMENTATION_SUMMARY_2026_01_03.md
│   │   ├── unified-synthesis-coordinator/
│   │   ├── last-listened-location/
│   │   └── sqlite-migration/
│   ├── code-detection/              # 🔬 In-progress research
│   ├── data-model/                  # Data model architecture
│   ├── pdf-image-extraction/        # PDF feature (in-progress)
│   └── playback-state-machine/      # State machine design
│
├── modules/                        # Package documentation
│   ├── README.md
│   ├── CORE_DOMAIN.md
│   ├── DOWNLOADS.md
│   ├── PLAYBACK.md
│   ├── TTS_ENGINES.md
│   ├── PLATFORM_ANDROID_TTS.md
│   └── UI.md
│
├── decisions/                      # Architecture decisions
│   └── TTS_DECISIONS.md
│
├── deployment/                     # App store deployment
│   ├── APP_STORE_DEPLOYMENT_GUIDE.md
│   ├── IOS_APP_STORE_DEPLOYMENT_GUIDE.md
│   ├── PLAY_STORE_DEPLOYMENT_PLAN.md
│   └── prerelease_checklist.md
│
├── legal/                          # Legal documents
│   ├── privacy_policy.md
│   └── terms_of_service.md
│
├── monetization/                   # Business model
│   └── freemium_model.md
│
└── archive/                        # 📦 Historical documentation
    ├── bugs/                       # Bug investigations
    ├── cleanup/                    # Cleanup reports
    ├── design/                     # UI design explorations
    ├── dev/                        # Development notes
    ├── features/                   # Archived feature work
    ├── fixes/                      # Fix templates
    ├── research/                   # Research investigations
    └── testing/                    # Test reports
```

## Categories Explained

### Architecture (Source of Truth)
The `architecture/` folder is the authoritative source for all system design:
- State machines for playback, synthesis, and UI
- Component interactions and data flow
- Performance optimization plans
- System audits and recovery guides

### Getting Started
Entry point for new developers. Covers:
- Environment setup (Flutter, Android SDK, etc.)
- Running the app locally
- Common setup issues and solutions
- Project structure overview

### Guides
Practical how-to documentation:
- Adding new features
- Running tests
- Debugging techniques
- Audio compression behavior

### Features
Feature documentation organized by status:
- **In-Progress**: Active development (`code-detection/`, `playback-state-machine/`)
- **Completed**: Finished implementations (`completed/`)
- Use `FEATURE_TEMPLATE.md` for new features

### Modules
Documentation for local packages:
- Package purpose and scope
- Public APIs
- Dependencies

### Decisions
Architecture Decision Records (ADRs):
- Why decisions were made
- Tradeoffs considered
- Alternatives evaluated

### Archive
Historical documentation preserved for reference:
- Bug investigations and fixes
- Completed cleanup reports
- UI design explorations
- Research and experiments

## Feature Branch Documentation

When working on a feature branch, create a feature-specific folder:

```
docs/features/feature-name/
├── README.md              # Feature overview
├── design.md              # Design decisions
├── implementation.md      # Implementation details
└── testing.md            # Testing strategy
```

Example:
```
docs/features/offline-sync/
├── README.md
├── design.md
├── implementation.md
└── testing.md
```

## Writing Guidelines

### File Naming
- Use kebab-case: `my-feature.md`, not `MyFeature.md`
- Be descriptive: `adding-oauth-support.md` not `oauth.md`

### File Organization
- One topic per file
- Keep files under 500 lines
- Link related documents
- Include a Table of Contents for long files

### Markdown Style
- Use `#` for main title (one per file)
- Use `##` and `###` for sections
- Include code examples with syntax highlighting
- Use tables for structured data
- Include diagrams for complex systems

### Documentation Process
1. Create documentation when implementing features
2. Update documentation when changing code
3. Include examples and code snippets
4. Link to related documentation
5. Keep documentation in version control with code

## Contributing to Documentation

Before submitting changes:
1. Check existing documentation for duplicates
2. Follow the structure and naming conventions
3. Link to related documents
4. Include examples where helpful
5. Proofread for clarity and accuracy

For more details, see [Contributing Guidelines](./guides/contributing.md).

## Maintenance

- **Review**: Update docs during code reviews
- **Deprecate**: Mark deprecated features clearly
- **Archive**: Move old docs to appropriate sections
- **Link**: Keep cross-references current

---

**Last Updated**: January 31, 2026
**Maintained By**: Development Team

For questions or suggestions about documentation, please file an issue or contact the team.
