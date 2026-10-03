---
name: weekly-report
description: Generate the team's weekly Slack report (French, emoji bullets) for kannar, ArendSyl, Sebastien Allemand and Alexandre Bocquier from axo git history and GitLab MRs. Use when asked for "the weekly report", "le weekly", or a report "for this week" for the team.
---

# Weekly team report

Produces a French Slack message summarising what the team shipped and what is in progress
over the reporting period, grouped by theme. Previous report is the format reference.

## Team (always all four — never forget kannar, the user)

| Person | Slack mention | git author match | GitLab username |
| --- | --- | --- | --- |
| kannar | `@kannar` | `--author=kannar` | `kannar` |
| ArendSyl (Jean-Baptiste Kaiser) | `@ArendSyl` | `--author=arendsyl` | `arendsyl` |
| Sébastien Allemand | `@Sebastien` | `-i --author=allemand` | `sebald` |
| Alexandre Bocquier | `@Alexandre Bocquier` | `-i --author=bocquier` | `AlexandreBocquier` |

If the user names only some people, still ask/confirm whether kannar is included — they expect to be.

## Period

Default: Monday → Friday of the current week (or since the day after the previous report's end
if the user pastes it). State the dates in the header as `DD/MM–DD/MM`.

## Gather (run from the axo repo root)

```bash
git fetch -q origin main
SINCE=YYYY-MM-DD   # first day of the period
# commits on main per person
git log origin/main --since=$SINCE -i --author=<match> --format='%ad %s' --date=short
# merged MRs in the period (merged_at is what counts, not author date)
glab mr list --author=<user> --merged -F json -P 40 | jq -r --arg s $SINCE '.[] | select(.merged_at >= $s) | "\(.iid) \(.merged_at[:10]) \(.title)"'
# open MRs (in-progress items)
glab mr list --author=<user> -F json -P 30 | jq -r '.[] | "\(.iid) \(.updated_at[:10]) \(.title)"'
```

Read an MR's description (`glab mr view <iid> -F json | jq -r .description`) only when the
title is too terse to summarise.

## Absences

**Ask the user whether anyone was off** (RTT, congés, maladie) before finalising — a person with
very few commits is the hint. An absent person gets a `:palm_tree: <Name> en RTT/congés …` line
right under the header, and their drafts/in-progress items are dropped (work they authored earlier
that merely *merged* during the period may stay, if it closes an item from the previous report).

## Format

- French text, English identifiers in backticks.
- Header: `weekly report @Alexandre Bocquier @ArendSyl @kannar @Sebastien (semaine du DD/MM–DD/MM) :`
- Group by **theme**, not by person (e.g. Base API, Token service, axo-init, Migration vers axo /
  parité legacy, SCA portal, Addons : sécurité et parité, Logs / drains, CI). Reuse the previous
  report's themes when they still fit so items carry over week to week.
- Per line: `:white_check_mark:` merged/done, `:hourglass_flowing_sand:` in progress (open MR),
  `:soon_tm:` planned. One line per outcome; fold several MRs into one line.
- Describe outcomes, not commits: no MR numbers, no commit-title paraphrase, no tests/docs/renames
  unless they are the deliverable.
- If an item was `:hourglass_flowing_sand:` in the previous report and merged now, report it as done.
- Output in a single fenced code block, ready to paste; follow with a short note on what was
  left out or assumed.
