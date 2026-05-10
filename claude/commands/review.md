---
name: review
description: Review code changes and provide feedback
---

Perform a code review of the changes between the current branch and the base branch.

Please:
1. Determine the default branch: `git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@'`
2. Get changed files: `git diff <default-branch>...HEAD --name-only`
3. Review the actual changes in each file
4. Provide a structured code review with:

**Overall Assessment:**
- Summary of changes
- Overall code quality rating (1-5 stars)

**Strengths:**
- What's done well
- Good patterns/practices observed

**Issues Found:**
Priority levels: 🔴 Critical | 🟡 Important | 🔵 Minor | 💡 Suggestion

For each issue:
- File and line reference
- Description of the issue
- Suggested fix
- Reasoning

**Security Concerns:**
Any potential security issues

**Performance Considerations:**
Potential performance impacts

**Testing Recommendations:**
What should be tested

Be constructive and focus on actionable feedback.
