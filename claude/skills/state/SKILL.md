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

**Fait**
- <résultat concret, avec la preuve courte : commit, MR !123, déployé, testé>

**En cours / en attente**
- <ce qui tourne ou attend quelqu'un, et qui/quoi>

**Prochain pas** : <la prochaine action, et qui la fait : moi ou toi>
```

Rules:

- Leave out an empty section rather than writing « rien ». Max ~4 bullets per section: merge the
  rest.
- Uncommitted or unpushed work, a running agent, or a promise not kept: say it, it is what gets
  lost when a session is closed.
- If the session wandered across several subjects, list them in **Session** in order, the current
  one last.
- Keep the user's own vocabulary (issue numbers, entity names, French terms they used).
- Do not continue the work after the status; wait for the user.
