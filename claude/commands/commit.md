---
name: commit
description: Generate a commit message from staged changes
---

Generate a conventional commit message based on the currently staged changes and commit it.

Please:
1. Check staged changes: `git diff --cached --stat`
2. Review the actual changes: `git diff --cached`
3. Generate a commit message following conventional commits format
4. Execute the commit with `git commit -m "..." -m "..."`

**Format:**
```
type(scope): subject

body (optional, if changes are complex)

footer (optional, for breaking changes or issue references)
```

**Types:**
- feat: New feature
- fix: Bug fix
- refactor: Code refactoring
- test: Adding/updating tests
- docs: Documentation changes
- style: Code style changes (formatting, etc)
- perf: Performance improvements
- chore: Build process, dependencies, etc
- ci: CI/CD changes

**Guidelines:**
- Subject: imperative mood, lowercase, no period, max 50 chars
- Body: explain what and why (not how), wrap at 72 chars
- Keep it concise and meaningful

Actually perform the commit after generating the message.
