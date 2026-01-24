# Audiobook Flutter V2 - Documentation Index

Welcome to the Audiobook Flutter V2 documentation. This guide will help you understand the codebase, set up development, and navigate the project.

## Quick Links

- **[Getting Started](./getting-started/)** - Setup, installation, and running the app
- **[Architecture](./ARCHITECTURE.md)** - Overall system design and component overview
- **[Architecture Details](./architecture/)** - State machines, improvements, and deep dives
- **[Features](./features/)** - In-depth documentation for specific features
- **[API Reference](./api-reference/)** - API and provider documentation
- **[Guides](./guides/)** - How-to guides for common tasks
- **[Fixes & Issues](./fixes/)** - Bug fixes and known issues
- **[Troubleshooting](./troubleshooting/)** - Common problems and solutions

## Documentation Structure

```
docs/
├── index.md                          # This file
├── ARCHITECTURE.md                   # System design overview
├── COPILOT_POLICY.md                # AI assistant guidelines
│
├── architecture/                    # Architecture deep dives
│   ├── audio_synthesis_pipeline_state_machine.md
│   ├── playback_screen_state_machine.md
│   ├── sleep_timer_state_machine.md
│   ├── tts_synthesis_state_machine.md
│   └── improvements/               # Audits and optimization plans
│       ├── improvement_opportunities.md
│       ├── tts_state_machine_audit.md
│       └── kokoro_performance_optimization.md
│
├── getting-started/                 # Project setup & onboarding
│   └── setup.md                     # Development environment setup
│
├── guides/                          # How-to guides
│   └── adding-new-features.md       # Feature development workflow
│
├── api-reference/                   # Provider & API docs
│   └── DOWNLOAD_URLS_REFERENCE.md   # Resource download URLs
│
├── features/                        # Feature-specific docs
│   ├── configuration-flexibility/  # Runtime config system
│   ├── downloads-improvements/     # Download system
│   ├── sleep-timer/               # Sleep timer feature
│   └── [feature-name]/            # Other features
│
├── fixes/                          # Bug fixes & issue resolutions
│   └── PLAYBACK_LOADING_ISSUE_ANALYSIS.md
│
├── modules/                        # Package documentation
│   ├── CORE_DOMAIN.md
│   ├── DOWNLOADS.md
│   ├── PLAYBACK.md
│   └── [package-name].md
│
├── decisions/                      # Architecture decisions
│   └── TTS_DECISIONS.md
│
├── dev/                           # Developer notes
│   ├── LOGGING_PLAN.md
│   ├── REMOTE_ADB_SETUP.md
│   └── TTS/
│
└── deployment/                    # App store deployment
    ├── APP_STORE_DEPLOYMENT_GUIDE.md
    └── IOS_APP_STORE_DEPLOYMENT_GUIDE.md
```

## Categories Explained

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
- Contributing process

### API Reference
Technical reference for:
- Riverpod providers and their dependencies
- Data models and structures
- Service interfaces and implementations

### Features
In-depth feature documentation:
- Feature design and architecture
- Implementation details
- Testing strategy
- Known limitations

### Fixes
Bug fix documentation:
- Issue description
- Root cause analysis
- Solution implemented
- Reproduction steps

### Troubleshooting
Problem-solving guides:
- Common errors and their solutions
- Error codes and meanings
- Performance tips
- FAQ

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

### Dev
Developer notes and work-in-progress:
- Temporary notes during development
- Experimental features
- Performance profiling results

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

**Last Updated**: January 24, 2026
**Maintained By**: Development Team

For questions or suggestions about documentation, please file an issue or contact the team.
