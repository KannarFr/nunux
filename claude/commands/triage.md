---
name: triage
description: Check your GitLab to-do list and triage each item — decide what you must answer yourself vs. what Claude can answer as you, then draft/post replies on approval
---

Triage the user's (kannar's) GitLab to-do list on the Clever Cloud instance.
For each item, decide whether **kannar must respond personally** or whether
**Claude can answer as kannar**, draft replies in his voice, and post them on
his approval.

Instance: `gitlab.corp.clever-cloud.com` (user `kannar`). Always export the host
so `glab` targets the right instance regardless of the current repo:
`export GITLAB_HOST=gitlab.corp.clever-cloud.com`

## Token budget (important — this runs on a loop)

Be cheap. **Never dump full `glab` JSON into context** — always trim with `--jq`.
Most items are bucketed from `action_name` alone with **zero extra API calls**.
Only deep-fetch the small subset that could plausibly be answered by you.

## Step 0 — Clear stale to-dos first (cleanup)

GitLab to-dos are notifications, NOT live status: merging/closing an MR or closing
an issue does **not** remove its to-do. Backlogs of hundreds accumulate. Before
triaging, clear everything already resolved. The to-do JSON carries `target.state`,
so no per-item lookups are needed.

Gotchas learned the hard way:
- The shell is **zsh** — `mapfile` doesn't exist and unquoted `$var` does NOT
  word-split. Use a `while read -r id` loop (pipe ids in), never `for id in $ids`.
- `glab api` has **no** `--jq` flag (only `glab todo list` does) — pipe through `jq`.
- The list paginates at 100 (`--page N`); a big backlog spans several pages.
- `glab todo done` is rate-limited on bulk runs — loop passes until a pass finds
  zero stale. For a long sweep, run it as a background bash command.

Sweep (clears merged/closed MRs + closed issues across pages, loops to zero):
```bash
export GITLAB_HOST=gitlab.corp.clever-cloud.com
for pass in $(seq 1 20); do
  ids=$(for pg in $(seq 1 8); do
    glab todo list --output=json -P 100 --page $pg 2>/dev/null \
      | jq -r '.[] | select((.target_type=="MergeRequest" and (.target.state=="merged" or .target.state=="closed")) or (.target_type=="Issue" and .target.state=="closed")) | .id'
  done | sort -u | grep -v '^$')
  [ -z "$ids" ] && break
  printf '%s\n' "$ids" | while read -r id; do glab todo done "$id" >/dev/null 2>&1; done
done
```
Note: archived repos are read-only — you can't comment/close there, only mark the
to-do done. Never mark an **open** item done as "cleanup" — that's a real backlog
item, not stale.

## Step 1 — Fetch the to-do list (one trimmed call)

```bash
export GITLAB_HOST=gitlab.corp.clever-cloud.com
glab todo list --output=json -P 100 --jq \
  '.[] | "\(.id)\t\(.action_name)\t\(.target_type)\t\(.target.iid)\t\(.project.id)\t\(.project.path_with_namespace)\t\(.target.web_url)\t\(.target.title)"'
```

That one call returns everything for classification. `action_name` values:
`review_requested`, `review_submitted`, `approval_required`, `assigned`,
`build_failed`, `unmergeable`, `mentioned`, `directly_addressed`, `marked`.

If the corp instance isn't authenticated, stop and tell kannar to run
`glab auth login --hostname gitlab.corp.clever-cloud.com`.

## Step 2 — Bucket from `action_name` first (no API calls)

Classify from the list alone — **do not fetch anything** for these:
- `review_requested` · `review_submitted` · `approval_required` → 🙋 (his call)
- `build_failed` · `unmergeable` → 🙋 (his blocked MR)
- `assigned` → 🙋 (his work)

Only `mentioned` · `directly_addressed` · `marked` are candidates for 🤖. Deep-fetch
**only those** (usually a handful), and only the triggering note — not the whole thread:

```bash
# newest notes only, trimmed to author + truncated body (glab api has NO --jq; pipe jq)
glab api "projects/{PROJECT_ID}/merge_requests/{IID}/notes?per_page=4&sort=desc&order_by=updated_at" \
  | jq -r '.[] | select(.system==false) | "\(.author.username): \(.body[0:280])"'
# issues: same with /issues/{IID}/notes  (work_items use the issue iid)
```

If a thread comes back empty, the mention is likely in the item **description**,
not a note — don't spend more calls chasing it; move that item to 🙋.

Cap deep fetches at ~8 items per run; if more, note the overflow and stop there.
Skip any where kannar's note is already the latest (nothing owed). Only read the MR
diff if a draft genuinely needs a fact from it — otherwise move the item to 🙋.

## Step 3 — Classify each item

Sort every item into one of two buckets.

### 🙋 MUST RESPOND PERSONALLY (flag to kannar — do NOT impersonate)
- **Review approvals / sign-off / LGTM** — approving code carries kannar's
  authority; he approves.
- **Architecture & design decisions**, RFC/ADR direction, trade-off calls.
- **Security items** (IDOR, auth, secrets, CVE triage decisions) — draft analysis
  is fine, but the decision/response is his.
- **Commitments** ("I'll do X by Y", scope/priority/deadline promises).
- **Interpersonal / sensitive / disagreement** threads.
- **Ambiguous asks** where you're not confident of the answer, or answering wrong
  would mislead a colleague.
- His **own blocked MRs** (`unmergeable`, `build_failed`) — surface the cause and
  suggested fix, but let him act (rebase/force-push/re-run are his calls).

### 🤖 CLAUDE CAN ANSWER AS KANNAR (draft in his voice, post on approval)
- **Factual clarifications** answerable from the code/diff/thread with confidence.
- **Acknowledgements** ("good catch, done in <sha>", "addressed, PTAL").
- **Simple thread resolutions** where the fix is obviously already made.
- **Pointers** ("see `path/to/file.rs:NN`", linking a related MR/issue).
- **Nudges** you're confident about (asking a reviewer to re-look after changes).

When unsure which bucket, default to 🙋 (personal). Err toward asking.

## Step 4 — Draft replies in kannar's voice

For 🤖 items, write the reply as kannar would:
- Concise, direct, lowercase-leaning, no corporate filler, no emoji-spam.
- Technical and specific; reference files as `path:line`, MRs as `!123`, issues
  as `#123`.
- French or English matching the thread's language.
- Never invent facts, shas, or promises. If a draft needs a fact you can't verify,
  move the item to 🙋 instead.
- Do NOT use the conventional-commits `!` marker anywhere (kannar adds that
  himself). See his commit-style preference.

## Step 5 — Present the plan, then act on approval

Output a single triage report:

```markdown
# GitLab triage — YYYY-MM-DD (N items)

## 🙋 Needs YOU (M)
- [!123](url) **Title** · project · _why it's yours_ · what's being asked (1 line)
  - suggested angle / draft analysis (optional, for his convenience)

## 🤖 I can answer as you (K) — review drafts below
- [!456](url) **Title** · project
  > proposed reply (verbatim, in his voice)
- [#78](url) **Title** · project
  > proposed reply

## ✅ Nothing owed / already handled (P)  — will mark done: <ids>
```

Then **stop and ask for approval** before any outward action. Offer:
`[a]ll` drafts, specific ids, `[e]dit` a draft, or `[s]kip`.

**Only after explicit approval**, post the approved drafts and mark items done:

```bash
# reply in an existing MR discussion thread
glab api -X POST "projects/{PROJECT_ID}/merge_requests/{IID}/discussions/{DISCUSSION_ID}/notes" -f body="..."
# or a fresh MR/issue comment
glab mr note {IID} -R {PROJECT_PATH} -m "..."
glab issue note {IID} -R {PROJECT_PATH} -m "..."
# mark the todo done once handled
glab todo done {TODO_ID}
```

Report back exactly what was posted (with links) and what was left for kannar.

## Safety rules
- **Posting a comment as kannar is outward-facing and hard to undo — never post
  without explicit per-batch approval.** Reading/analysis needs no approval.
- Never approve/merge/close/resolve on his behalf, even under 🤖.
- Never mark a 🙋 item done automatically — he clears those himself.
- If nothing needs attention, say so in one line and stop.

## Autorun (keep it lean)
Safe to schedule the analysis pass: `/loop 30m /triage` or a `/schedule` cron.
To stay cheap on repeat runs, when nothing changed since the last run emit a single
line (`no new todos since HH:MM`) and stop — don't re-fetch discussions for items
already triaged. On loop runs, keep the report to the 🙋/🤖 tables only (drop the
✅ section unless asked). Posting still waits for approval, so autorun never speaks
as kannar unattended.
