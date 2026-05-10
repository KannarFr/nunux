---
name: mr
description: Generate GitLab MR title and description from git diff with master
---

Generate a SHORT merge request description (max 40 lines) by comparing the current branch with the master/main branch.

Please:
1. Determine the default branch name (master or main) using: `git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@'`
2. Get the diff statistics: `git diff <default-branch>...HEAD --stat`
3. Get commit messages: `git log <default-branch>..HEAD --oneline`
4. Optionally read key changed files to understand context (only if absolutely necessary)
5. Generate a CONCISE merge request description with:

**Title Format (single line):**
```
type(scope): brief description
```
Types: feat, fix, refactor, test, docs, chore, style, perf, ci, build

**Description Format (keep under 40 lines total):**
- **Summary**: 2-3 sentences max on what and why
- **Key Changes**: 3-6 bullet points of main modifications only
- **Testing**: 1-2 sentences on how to test or reference existing tests

**CRITICAL**: Keep the ENTIRE output under 40 lines. Be extremely concise. Skip minor details, formatting changes, or obvious information. Focus only on what reviewers absolutely need to know.
