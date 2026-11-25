---
name: state
description: Give a TL;DR, in French, of what this Claude session is about and where it stands - goal, done, in progress, waiting, next step - so the user can find their bearings when juggling several sessions. Use when the user types /state, or asks « on en est où ? », « c'est quoi cette session ? », « je suis perdu », « tl;dr », « résume ».
---

# /state: où en est cette session

The user switches between several Claude sessions and has lost track of this one. They want to
recognise it in five seconds and know what to do next. Answer in French, from evidence, short.

## Gather (read-only, one batch)

- The conversation itself: the user's requests (their words, not your summaries), what was done,
  what was promised, what was left hanging. After a context compaction, rely on the summary plus
  the checks below.
- `pwd`, `git branch --show-current`, `git status --short | head`, `git log --oneline -5`, and
  whether the branch is ahead of its remote (`git status -sb | head -1`).
- Background agents, shells, workflows or `ws1 run`s started by this session that are still
  running or whose result was not read.
- Anything this session wrote to a tracking file (`axo/todo.md`, an `admin/` file, a plan).

Don't open new investigations: this is a status, not a work step.

## Answer

Exactly this shape, nothing before it, each line short:

```
**Session** : <repo> (`<branche>`) — <le sujet en une phrase, assez concret pour reconnaître la session>

**TL;DR** : <1-2 phrases : où on en est vraiment>

**Index**
1. <sujet> — <issue / MR en lien cliquable>
2. …

| # | Sujet | État actuel | Attendu | Qui / bloqué par |
|---|---|---|---|---|
| 1 | <sujet> | <ce qui est vrai maintenant, avec la preuve courte : MR !123 mergée, déployé `abc1234`, en draft> | <l'état final visé> | <moi, toi, @personne, ou ce qui bloque> |

**En cours / en attente**
- <ce qui tourne (agents, shells, trains) ou attend une décision, et qui/quoi>

**Prochain pas** : <la prochaine action, et qui la fait : moi ou toi>
```

Rules:

- **Index and table, always**, even for a single subject: one row per subject, same numbers in
  both. A subject is what the user would name (an issue, an incident, a feature), not each MR:
  group the MRs of one subject in its row.
- **Current vs expected** is the point of the table: « État actuel » says what is true now, from
  evidence (merged, deployed sha, draft, waiting on X since <date>); « Attendu » says the end state
  the user asked for, so the gap is visible. A finished subject keeps its row, with « Attendu »
  reached (« = fait »), until the session is closed.
- Links: issues and MRs as clickable links (full URL, or the forge's short form when the
  terminal renders it), so the index doubles as navigation.
- Uncommitted or unpushed work, a running agent, or a promise not kept: say it in the row and in
  « En cours », it is what gets lost when a session is closed.
- Leave out an empty section rather than writing « rien ». Merge bullets past ~4 per section.
- Keep the user's own vocabulary (issue numbers, entity names, French terms they used).
- An argument after `/state` (e.g. a format request) adjusts this shape for that answer.
- Do not continue the work after the status; wait for the user.
