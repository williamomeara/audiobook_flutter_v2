# Bug Fixes Documentation Template

Use this template when documenting resolved issues.

## Copy this for each fix

```bash
cp docs/fixes/FIX_TEMPLATE.md docs/fixes/your-issue-name.md
```

Then fill in the sections below:

---

# [Issue Title]

## Issue Summary

Brief one-sentence description of the issue.

## Symptoms

How the bug manifests to users:
- What appears broken?
- What error messages are shown?
- When does it occur?
- How frequently?

### Steps to Reproduce

```
1. Start the app
2. Navigate to [screen]
3. Perform action [X]
4. Observe error/behavior [Y]
```

## Root Cause Analysis

### Investigation Process

- What debugging techniques were used?
- What logs/error messages helped identify the issue?
- What hypothesis was tested?

### Root Cause

Detailed explanation of what was causing the issue:
- Code path that had the problem
- Why it was behaving incorrectly
- Any contributing factors

### Impact

- Severity: Critical / High / Medium / Low
- Affected users: All / Some / Specific scenarios
- Data loss risk: Yes / No
- Performance impact: Yes / No

## Solution

### Approach

High-level explanation of how the issue was fixed.

### Implementation Details

```dart
// Before (broken code)
void problemFunction() {
  // Issue description
}

// After (fixed code)
void problemFunction() {
  // Fix explanation
}
```

### Files Changed

```
- lib/file1.dart        (Line XX: Changed X to Y)
- lib/file2.dart        (Line YY: Added Z)
- lib/file3.dart        (Line ZZ: Removed A)
```

### Why This Fix Works

Explanation of why this solution resolves the issue:
- What was changed and why
- How it prevents the issue from recurring
- Any tradeoffs made

### Alternatives Considered

1. **Alternative Approach 1**
   - Pros: 
   - Cons: 
   - Why not chosen:

2. **Alternative Approach 2**
   - Pros: 
   - Cons: 
   - Why not chosen:

## Testing

### Verification Steps

```
1. [Action 1]
2. [Action 2]
3. [Expected result]
```

### Test Coverage

- [ ] Added unit tests
- [ ] Added widget tests
- [ ] Added integration tests
- [ ] Manual testing completed
- [ ] Edge cases tested

### Test Results

- Total tests: XX
- Passing: XX
- Failing: 0
- Coverage: XX%

## Backwards Compatibility

- Breaking changes: None / Yes (describe)
- Migration required: No / Yes (describe)
- Deprecations: None / Yes (describe)

## Performance Impact

- Performance improvement: Yes / No
- Memory impact: None / Positive / Negative
- Load time change: None / Faster / Slower
- Benchmark results: [if applicable]

## Related Issues

- Closes: #123
- Related to: #456, #789
- Duplicates: [if applicable]

## Deployment

### Release Notes

Include a user-friendly description for release notes.

### Migration Guide

If users need to take action:
1. Step 1
2. Step 2
3. Step 3

### Rollout Plan

- [ ] Deployed to staging
- [ ] Tested in staging
- [ ] Approved for production
- [ ] Deployed to production
- [ ] Monitored in production

## Monitoring

### Metrics to Watch

- Error rate: Should decrease from XX% to 0%
- Performance metric: [specific metric]
- User impact: [how to measure]

### Alert Thresholds

- If [metric] exceeds [threshold], [action]
- If [error] occurs more than [N] times, [action]

## Follow-up

### Future Improvements

- [ ] Refactor to prevent similar issues
- [ ] Add better error handling
- [ ] Improve logging
- [ ] Update documentation

### Related Work

- Issue [#123]: Similar issue in component X
- Issue [#456]: Preventive measure for component Y

## Questions & Notes

- Open questions
- Notes for future maintainers
- Technical debt added/removed

---

## Metadata

| Field | Value |
|-------|-------|
| **Issue Number** | #123 |
| **Branch** | `fix/issue-title` |
| **Fix Date** | YYYY-MM-DD |
| **Fixed By** | Developer Name |
| **Reviewed By** | Reviewer Name |
| **Status** | Fixed / Pending Review / In Progress |

## Version History

| Date | Author | Change |
|------|--------|--------|
| YYYY-MM-DD | Name | Initial documentation |
