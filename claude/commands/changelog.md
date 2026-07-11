# Slack Changelog Skill

Generate a Slack-ready changelog of the merge requests **you authored and that got merged** in a given time window.

Default window: **yesterday and today**. The user may override with an argument (e.g. `this week`, `since 2026-06-25`, `last 3 days`).

## Instructions

1. Determine your GitLab username and the host you're authenticated against:
```bash
glab auth status 2>&1
```
Pick the host where you are logged in (e.g. `gitlab.corp.clever-cloud.com`) and note the username (e.g. `kannar`).

2. Compute the start of the window from today's date.
   - "yesterday and today" → `updated_after` = yesterday at `00:00:00Z`.
   - Honor any explicit range the user gave instead.

3. Fetch your merged MRs across all projects (`scope=all`), filtered to the window. Use `--hostname` for the right instance:
```bash
glab api --hostname <HOST> \
  "merge_requests?author_username=<USER>&state=merged&updated_after=<START>T00:00:00Z&scope=all&per_page=50" \
  2>/dev/null \
  | jq -r '.[] | "\(.merged_at // "n/a")\t!\(.iid)\t\(.project_id)\t\(.title)\t\(.web_url)"' | sort
```
   - `updated_after` is the available server-side filter; **re-check `merged_at`** on each result and drop any whose `merged_at` falls outside the requested window (an MR can be updated in-window but merged earlier).

4. For each in-window MR, pull its description to summarize accurately (don't invent — base the summary on the description and title):
```bash
glab api --hostname <HOST> "projects/<PROJECT_ID>/merge_requests/<IID>" 2>/dev/null | jq -r '.description'
```

5. Write the changelog as **Slack mrkdwn** (not GitHub markdown). Rules:
   - Bold with single `*asterisks*`, not `**`.
   - Links as `<url|label>`, label like `repo!123`.
   - Bullets with `•`.
   - Lead each entry with the repo name + the conventional-commit type from the title (`feat`, `fix`, `refactor!`, `test`, …).
   - 1–3 sentence plain-language summary of *what changed and why it matters*, not a file list.
   - Group related MRs together when they're part of one effort.
   - Reference linked issues/MRs by their short ids when the description calls them out.

6. Suggested output shape:
```
:rocket: *Changelog — <Name> (<date range>)*

*<theme / grouping headline>*

• *<repo>* — `<type>`: <short title> (`!<iid>`)
   <1–3 sentence summary of what changed and the impact.>
   <url|repo!iid>

*TL;DR:* <one-line bottom line.> :white_check_mark:
```

7. State plainly which day(s) the MRs landed on, and call out if nothing was merged today (vs. yesterday). End by offering to shorten the format or post it.

## Notes
- If multiple GitLab hosts are configured, only query the one(s) where auth succeeded.
- If zero MRs match, say so clearly rather than padding.
- Keep it scannable — this goes in a Slack channel, so favor brevity over completeness.
- Don't include the Claude Code generation footer in the changelog output.
