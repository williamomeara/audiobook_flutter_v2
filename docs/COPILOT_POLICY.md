Copilot CLI usage policy

- Do NOT commit or push repository changes to remote unless explicitly requested by the user.
- The Copilot CLI will make edits locally and present exact diffs or file contents for user approval before committing.
- The Copilot CLI will ask for explicit permission before running git commit or git push operations.

If you want this policy committed and pushed to the remote repository, reply "commit and push" and I will proceed.

● Added directory to allowed list: /home/william/Projects/audiobook_flutter/

This is the old version of this project and can be used as a reference for learning purposes.

---

## Documentation Strategy

### Documentation Structure

The project uses an organized documentation system with the following structure:

```
docs/
├── index.md                    # Documentation hub & navigation
├── ARCHITECTURE.md             # System design
├── getting-started/            # Setup & onboarding
├── guides/                     # How-to guides
├── api-reference/              # API documentation
├── features/                   # Feature-specific docs
├── fixes/                      # Bug fix documentation
├── troubleshooting/            # Problem solving
├── modules/                    # Package documentation
├── decisions/                  # Architecture decisions
└── dev/                        # Developer notes
```

### When Working on Features

1. **Feature Branch**: Create a feature branch following the pattern `feature/feature-name`

2. **Documentation**: Create feature documentation:
   ```bash
   mkdir -p docs/features/feature-name
   cp docs/features/FEATURE_TEMPLATE.md docs/features/feature-name/README.md
   ```

3. **Update as You Code**: Document design decisions, implementation details, and testing strategy

4. **Include Examples**: Add code snippets and usage examples

### When Fixing Bugs

1. **Fix Branch**: Create a fix branch following the pattern `fix/issue-name`

2. **Document the Fix**: Create fix documentation:
   ```bash
   cp docs/fixes/FIX_TEMPLATE.md docs/fixes/issue-name.md
   ```

3. **Include Root Cause**: Explain why the bug occurred and how the fix prevents it

### Documentation Requirements

- All features must be documented using the FEATURE_TEMPLATE.md
- All significant bug fixes must be documented using the FIX_TEMPLATE.md
- Documentation must be updated alongside code changes
- Documentation is reviewed as part of code review
- Keep documentation in version control with code

### Best Practices

✅ **Document as you code** - Don't leave it until the end
✅ **Include examples** - Code snippets help understanding
✅ **Link related docs** - Cross-references are important
✅ **Keep files focused** - One topic per file
✅ **Update with code changes** - Keep docs in sync

❌ **Don't** let documentation get out of sync with code
❌ **Don't** wait until the end to document
❌ **Don't** create massive documents (>500 lines)
❌ **Don't** forget to update docs during code review

### Key Files

- `DOCUMENTATION_STRUCTURE.md` - Overview of the documentation system
- `docs/index.md` - Documentation home page
- `docs/ARCHITECTURE.md` - System architecture overview
- `docs/guides/adding-new-features.md` - Feature development workflow
- `docs/features/FEATURE_TEMPLATE.md` - Template for new features
- `docs/fixes/FIX_TEMPLATE.md` - Template for bug fixes

### For More Information

See `DOCUMENTATION_STRUCTURE.md` at the root of the project for complete documentation guidelines.