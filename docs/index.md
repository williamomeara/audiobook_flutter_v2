# Audiobook Flutter V2 - Documentation Index

Welcome to the Audiobook Flutter V2 documentation. This guide will help you understand the codebase, set up development, and navigate the project.

## Quick Links

- **[Getting Started](./getting-started/)** - Setup, installation, and running the app
- **[Architecture](./ARCHITECTURE.md)** - Overall system design and component overview
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
├── README.md                         # Main documentation README
├── TTS_IMPLEMENTATION_COMPLETE.md   # TTS feature summary
├── DOWNLOAD_URLS_REFERENCE.md       # Resource download URLs
├── COPILOT_POLICY.md                # AI assistant guidelines
│
├── getting-started/                 # Project setup & onboarding
│   ├── setup.md                     # Development environment setup
│   ├── running-locally.md           # How to run the app
│   └── troubleshooting.md           # Common setup issues
│
├── guides/                          # How-to guides
│   ├── adding-new-features.md       # Feature development workflow
│   ├── testing.md                   # Testing strategies
│   ├── debugging.md                 # Debugging tips
│   └── contributing.md              # Contributing guidelines
│
├── api-reference/                   # Provider & API docs
│   ├── providers.md                 # Riverpod providers
│   ├── models.md                    # Data models
│   └── services.md                  # Core services
│
├── features/                        # Feature-specific docs
│   ├── downloads-improvements/      # Download system
│   ├── onnx/                        # TTS ONNX Runtime
│   └── [feature-name]/             # New features (branch-specific)
│
├── fixes/                          # Bug fixes & issue resolutions
│   ├── playback-loading-issue.md   # Infinite loading state fix
│   └── [issue-name].md             # Other resolved issues
│
├── troubleshooting/                # Problem solving
│   ├── playback-issues.md          # Playback-related problems
│   ├── download-failures.md        # Download-related issues
│   └── [problem-area].md           # Other common issues
│
├── modules/                        # Package documentation
│   └── [package-name]/            # Package-specific docs
│
├── decisions/                      # Architecture decisions
│   └── [ADR].md                    # Architecture Decision Records
│
└── dev/                           # Developer notes
    ├── TTS/                       # TTS development notes
    └── [area]/                    # Area-specific notes
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

**Last Updated**: January 7, 2026
**Maintained By**: Development Team

For questions or suggestions about documentation, please file an issue or contact the team.
