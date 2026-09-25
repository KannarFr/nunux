---
name: gitlab-mail
description: Check the unread Thunderbird GitLab mails (Clever Cloud Gmail, INBOX/GitLab) and mark read everything that is merged or doesn't mention kannar, keeping axo-global and non-axo threads unread
---

Triage kannar's unread GitLab notification mails. Folder `INBOX/GitLab` on the
Clever Cloud Gmail account (Thunderbird `server1`). Bodies aren't cached
offline, so the scripts here talk IMAP directly using Thunderbird's saved
Google OAuth login for that account (XOAUTH2).

## Steps

Scripts live next to this file (`~/.claude/skills/gitlab-mail/`); run them from
that directory. Put `threads.json` in the scratchpad.

1. `python3 fetch.py <scratchpad>/threads.json` — read-only (`BODY.PEEK`, never
   sets `\Seen`). Prints one line per thread: index, flags (`M` = a real
   `@kannar` mention, `m` = a merged notification seen), mail count, project,
   subject. Details (notification reasons, snippets) are in the JSON if a
   subject is ambiguous.
2. Classify every thread with the rule below.
3. Tell the user the **keep** list (index + one-line reason each), then
   `python3 mark.py <scratchpad>/threads.json <idx> <lo-hi> ...` with the rest.
   It marks by UID, never sequence number.
4. Report: N mails / M threads marked read, and the keep list.

## The rule (kannar's words)

> Mark read everything merged or not directly mentioning kannar, *except*
> axo-global (non-module-specific) stuff.

Keep **unread**:
- Real `@kannar` mentions. The `Reviewers: kannar, …` footer is on almost every
  axo MR and is **not** a mention (fetch.py already ignores it). Being added as
  a reviewer (`review_requested`) is not a mention either.
- axo-global work, even if merged: `base` / `base!` wire-breaking changes,
  workspace CI (`ci:`, `ci(...)`, `feat(ci)`), release, RFCs, workspace dev
  tooling (`devel`), workspace docs (`docs(agent)`, `docs(deps)`), shared core
  traits/fakes (messaging broker, AMQP listeners), cross-provider pieces
  (addon-outbox), `openapi`, api-wide infra (e.g. `database` pools).
- Anything outside `clever-cloud/axo` (ovd, rfcs, Dashboard, ansible…).

Everything else — a single product/module (`postgresql`, `cellar`,
`product-mysql`, `kubernetes`, `billing`, `keycloak`, `faas-executor`,
`docs(api)` for one service…) — is marked read, merged or not.

## If it fails

- `PK11SDR_Decrypt failed`: Thunderbird has a primary password set, or the
  profile glob picked the wrong profile (the live one is `*.default-release`).
- Token exchange `invalid_grant`: the saved login was revoked; open Thunderbird
  once so it re-authenticates the account, then retry.
