---
name: pr
description: Generate GitHub PR title and description from git diff with main
---

Generate a pull request description by comparing the current branch with the main/master branch.

Please:
1. Determine the default branch name (main or master) using: `git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@'`
2. Get the diff statistics: `git diff <default-branch>...HEAD --stat`
3. Get commit messages: `git log <default-branch>..HEAD --oneline`
4. Optionally read key changed files to understand context
5. Generate a pull request description with:

**Title Format (single line):**
```
type(scope): brief description
```
Types: feat, fix, refactor, test, docs, chore, style, perf, ci, build

**Description Format:**
## What
Brief description of changes (2-3 sentences)

## Why
Context and motivation for the changes

## How
Key technical decisions and approach

## Changes
- Bullet list of main changes
- Focus on user-facing changes
- Include breaking changes if any

## Testing
How the changes were tested (if applicable)

Keep it concise (200-400 words) and focused on what reviewers need to know.
