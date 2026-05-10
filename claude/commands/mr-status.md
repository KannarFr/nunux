# MR Status Report Skill

Generate a report of open merge requests with blocking analysis.

## Instructions

1. First, fetch the list of open MRs:
```bash
glab mr list -F json -P 100
```

2. For each MR, fetch its discussions:
```bash
glab api "projects/:id/merge_requests/{MR_IID}/discussions"
```

3. For each **unresolved** thread (where `notes[0].resolvable == true` and `notes[0].resolved == false`), analyze who is blocking:

**Blocking Logic:**
- Look at the **last message** in the thread (`notes[-1]`)
- If last message is from someone OTHER than the MR author → **MR author is blocking** (needs to respond/fix)
- If last message is from the MR author → **thread opener is blocking** (needs to resolve or continue review)

4. Generate a compact markdown report with this format:

```markdown
# Open MRs Report (YYYY-MM-DD)

## Blocked by Author (need to respond/fix)
- [!123](url) **Title** @author ← needs to address feedback from @reviewer1
  - @reviewer1: "comment preview..." [→](link)

## Blocked by Reviewers (need to resolve)
- [!456](url) **Title** @author ← waiting on @reviewer2 to resolve
  - @reviewer2: "comment preview..." (author responded) [→](link)

## Ready / No blockers
- [!789](url) **Title** @author → @reviewer1 @reviewer2

## Stale (no activity >7 days)
- [!101](url) **Title** @author (15 days stale)

## Draft
- [!102](url) **Title** @author
```

5. At the end, provide a **summary** of who to ping:
```markdown
## Action Required
- **@author1**: Respond to feedback on !123, !124
- **@reviewer1**: Resolve threads on !456
- **@reviewer2**: Review pending on !789, !790
```

## Notes
- Group MRs by status to make it actionable
- Keep thread previews short (~60 chars)
- Calculate staleness from `updated_at` field
- Skip draft MRs from blocking analysis (they're expected to be WIP)
