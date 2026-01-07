# Documentation Organization System

## Overview

The Audiobook Flutter V2 project now uses an organized, scalable documentation system based on industry best practices. This document explains the structure and how to use it.

## Directory Structure

```
docs/
├── index.md                              # Documentation home & navigation hub
├── ARCHITECTURE.md                       # System design overview
├── COPILOT_POLICY.md                     # AI assistant guidelines
├── TTS_IMPLEMENTATION_COMPLETE.md        # TTS feature summary
├── IMPLEMENTATION_SUMMARY_2026_01_03.md # Implementation status
├── DOWNLOAD_URLS_REFERENCE.md            # Resource URLs
├── kokoro_performance_optimization.md    # Performance notes
│
├── getting-started/                      # 📖 Onboarding & Setup
│   ├── setup.md                         # Environment setup guide
│   ├── running-locally.md               # How to run the app
│   └── troubleshooting.md              # Setup issues
│
├── guides/                               # 📚 How-to Guides
│   ├── adding-new-features.md          # Feature development workflow
│   ├── testing.md                       # Testing strategy
│   ├── debugging.md                     # Debugging techniques
│   └── contributing.md                  # Contributing guidelines
│
├── api-reference/                        # 🔌 API Documentation
│   ├── providers.md                     # Riverpod providers reference
│   ├── models.md                        # Data models
│   └── services.md                      # Core services
│
├── features/                             # ✨ Feature Documentation
│   ├── FEATURE_TEMPLATE.md              # Template for new features
│   ├── downloads-improvements/          # Download system feature
│   ├── onnx/                           # TTS ONNX implementation
│   └── [feature-name]/                  # New feature branches
│       ├── README.md                    # Feature overview
│       ├── design.md                    # Design decisions
│       ├── implementation.md            # Implementation details
│       └── testing.md                   # Testing strategy
│
├── fixes/                                # 🐛 Bug Fixes & Issues
│   ├── FIX_TEMPLATE.md                  # Template for bug fixes
│   ├── PLAYBACK_LOADING_ISSUE_ANALYSIS.md  # Specific fix
│   └── [issue-name].md                  # Other resolved issues
│
├── troubleshooting/                      # ❓ Problem Solving
│   ├── playback-issues.md              # Playback problems
│   ├── download-failures.md            # Download issues
│   └── [problem-area].md               # Other common issues
│
├── modules/                              # 📦 Package Documentation
│   ├── README.md                        # Modules overview
│   ├── CORE_DOMAIN.md                   # Core domain package
│   ├── DOWNLOADS.md                     # Downloads package
│   ├── PLAYBACK.md                      # Playback package
│   ├── TTS_ENGINES.md                   # TTS engines package
│   ├── PLATFORM_ANDROID_TTS.md          # Android TTS bindings
│   ├── APP_LAYER.md                     # App providers & controllers
│   ├── UI.md                            # UI components
│   └── GUTENBERG_IMPORT.md              # Gutenberg import feature
│
├── decisions/                            # 📋 Architecture Decisions
│   ├── TTS_DECISIONS.md                 # TTS architecture decisions
│   └── [adr-name].md                    # Other ADRs
│
└── dev/                                  # 👨‍💻 Developer Notes
    ├── TTS/                             # TTS development notes
    │   ├── README.md
    │   ├── Executive_summary.md
    │   ├── Quick_start_visual.md
    │   ├── Strategy_comparison.md
    │   └── TTS_implementation_improved.md
    └── [area]/                          # Other area-specific notes
```

## Key Features

### 1. **Feature Branch Documentation**

For each feature branch, create a dedicated folder:

```bash
# Create feature documentation
mkdir -p docs/features/your-feature-name
cp docs/features/FEATURE_TEMPLATE.md docs/features/your-feature-name/README.md
```

**Update the template with:**
- Feature overview and motivation
- Architecture and design
- Implementation details
- Testing strategy
- Known limitations

### 2. **Bug Fix Documentation**

For each resolved issue, create a fix document:

```bash
# Document the fix
cp docs/fixes/FIX_TEMPLATE.md docs/fixes/issue-name.md
```

**Include:**
- Symptoms and reproduction steps
- Root cause analysis
- Solution implemented
- Testing verification
- Performance impact

### 3. **Centralized Navigation**

All documentation starts from `docs/index.md`:
- Quick links to major sections
- Directory structure overview
- Contributing guidelines
- Maintenance policies

### 4. **Templates for Consistency**

Two main templates ensure consistent documentation:

- **FEATURE_TEMPLATE.md**: For new features
  - Design & architecture
  - Implementation & testing
  - Performance & limitations
  - Monitoring & rollout

- **FIX_TEMPLATE.md**: For bug fixes
  - Issue description
  - Root cause analysis
  - Solution & alternatives
  - Testing & verification

## How to Use

### For Developers

1. **Starting a Feature**
   ```bash
   # Read getting started guides
   docs/getting-started/setup.md
   
   # Learn the architecture
   docs/ARCHITECTURE.md
   
   # Read adding features guide
   docs/guides/adding-new-features.md
   ```

2. **Implementing a Feature**
   ```bash
   # Create feature documentation
   mkdir -p docs/features/my-feature
   cp docs/features/FEATURE_TEMPLATE.md docs/features/my-feature/README.md
   
   # Document as you code
   # Update docs with design decisions
   # Finalize with testing & performance notes
   ```

3. **Fixing a Bug**
   ```bash
   # Document the fix
   cp docs/fixes/FIX_TEMPLATE.md docs/fixes/my-issue-fix.md
   
   # Fill in root cause analysis
   # Explain the solution
   # Add testing verification
   ```

### For Reviewers

- Review documentation alongside code
- Ensure docs are updated with code changes
- Check docs follow templates and guidelines
- Verify links are correct and not broken

### For Maintainers

- Keep documentation current
- Archive old feature docs
- Update deprecated features
- Review & improve existing docs

## Writing Guidelines

### File Naming Convention
```
✓ feature-name.md              # kebab-case
✓ bug-fix-for-playback.md
✗ FeatureName.md              # No PascalCase
✗ feature_name.md             # No snake_case (except dirs)
```

### Structure Within Files
```markdown
# Main Title (one per file)

## Section 1
Content...

### Subsection 1.1
Details...

## Section 2
Content...

### Code Example
[fenced code block with language]

## Related Documentation
- [Link to related doc](../path/to/doc.md)
```

### Linking Between Docs
```markdown
# Internal links
[Architecture](../ARCHITECTURE.md)
[Feature Guide](./adding-new-features.md)

# External links
[Flutter Docs](https://flutter.dev/docs)
```

## Best Practices

✅ **DO:**
- Write documentation as you code
- Include examples and code snippets
- Link related documentation
- Keep files focused on one topic
- Use clear, concise language
- Update docs when code changes
- Include diagrams for complex systems

❌ **DON'T:**
- Let documentation get out of sync with code
- Write documentation after everything is done
- Create massive documents (>500 lines)
- Duplicate information across docs
- Use unclear jargon without explanation
- Forget to update docs during reviews

## Maintenance

### Regular Tasks
- **Monthly**: Review and update outdated docs
- **Per PR**: Ensure docs are updated with code changes
- **Per Release**: Update version-specific documentation
- **Quarterly**: Archive old feature docs, update evergreen content

### Deprecation Process
1. Mark feature as deprecated in docs
2. Add migration guide if needed
3. Link to replacement docs
4. Archive old docs after grace period

## Integration with CI/CD

Documentation is part of code review:
- Docs changes require review like code changes
- Broken documentation links flagged in CI
- Markdown linting enforces consistency
- Documentation should be updated before merge

## Tools & Utilities

### Markdown Linting
```bash
# Install markdownlint
npm install -g markdownlint-cli

# Check all docs
markdownlint docs/
```

### Link Validation
```bash
# Check for broken links (coming soon)
markdown-link-check docs/**/*.md
```

### Build Documentation Site
```bash
# Future: Static site generation from markdown
# Could use MkDocs, Jekyll, or Docusaurus
```

## Quick Links

- 📖 **[Documentation Home](./docs/index.md)** - Start here
- 🚀 **[Getting Started](./docs/getting-started/setup.md)** - Setup guide
- 📚 **[Feature Development](./docs/guides/adding-new-features.md)** - How to add features
- 🏗️ **[Architecture](./docs/ARCHITECTURE.md)** - System design
- 🐛 **[Bug Fixes](./docs/fixes/)** - Documented fixes
- 💡 **[Guides](./docs/guides/)** - How-to guides

## Examples in Repository

### Feature Documentation Example
```
docs/features/downloads-improvements/
├── README.md                    # Feature overview
├── IMPLEMENTATION_PLAN.md       # Step-by-step plan
├── IMPROVEMENTS_RECOMMENDATIONS.md
└── STEP_BY_STEP_PLAN.md
```

### Fix Documentation Example
```
docs/fixes/
├── FIX_TEMPLATE.md
└── PLAYBACK_LOADING_ISSUE_ANALYSIS.md  # Complete fix doc
```

## Getting Started

1. **Read**: `docs/index.md` - Documentation overview
2. **Setup**: `docs/getting-started/setup.md` - Environment setup
3. **Learn**: `docs/ARCHITECTURE.md` - System architecture
4. **Develop**: `docs/guides/adding-new-features.md` - Feature workflow

---

## Questions?

If you have questions about the documentation structure:
1. Check existing similar documentation
2. Review the relevant template
3. Ask on team communication channel
4. Create an issue for documentation improvements

---

**Created**: January 7, 2026
**Version**: 1.0
**Maintainer**: Development Team
