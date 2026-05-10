---
name: explain
description: Explain what changed between branches in simple terms
---

Explain the changes between the current branch and the base branch in simple, non-technical terms.

Please:
1. Determine the default branch: `git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@'`
2. Get the diff: `git diff <default-branch>...HEAD --stat`
3. Review key changed files
4. Provide an explanation that:

**Target audience:** Someone who understands the business/product but not necessarily the code

**Format:**
**Summary (1 sentence)**
What was done in plain English

**Details (3-5 bullet points)**
- What changed (in user/business terms)
- Why it matters
- Any user-visible impact

**Technical Notes (optional)**
Brief technical context if needed for understanding

**Risks/Considerations**
Any important caveats or things to be aware of

Use simple analogies and avoid jargon where possible.
