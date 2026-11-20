---
name: ask
description: Interview the user with interactive multiple-choice questions, in French, each one self-contained and grounded in what the session and the repo already show, with a recommended answer and alternatives. Use when the user types /ask, optionally followed by a topic ("/ask le design du cache"), or says « pose-moi des questions », « interroge-moi », « demande-moi ce qu'il te faut ». Without a topic, ask about the open decisions of the current session.
---

# /ask: interroge l'utilisateur

The user wants to answer questions, not read a wall of text. You do the homework first, then ask
them through the `AskUserQuestion` tool, in French, so they only have to pick or correct.

## 1. Find the subject

- `/ask <sujet>`: that subject.
- `/ask` alone: the decisions this session is blocked on or about to take by default. Re-read the
  conversation; if nothing is open, ask what they want to work on, with 2-4 guesses drawn from the
  repo (`git status`, recent commits, TODO files, the repo's CLAUDE.md).

## 2. Homework before the first question

Never ask what you can find out. Read the relevant files, the git state, the memory, the
conversation. Each question must be one only the user can answer: a preference, a priority, a fact
outside the machine, a trade-off. If a sensible default exists and the choice is cheap to reverse,
don't ask: note it as « je pars sur X » in the final recap.

## 3. Asking

- `AskUserQuestion`, 1 to 4 questions per round, most structuring first (a later question can
  depend on its answer: then ask it in the next round).
- **Self-contained**: the dialog hides everything you wrote before. Each question says in one
  sentence what it is about and what you found that motivates it (« Le cache actuel expire au
  bout de 5 min et `foo.rs` le vide à chaque déploiement : … ? »). Name files, entities, numbers.
- **Options are suggestions**: 2 to 4 concrete, mutually exclusive answers. Your recommendation
  first, its label ending in « (recommandé) », its description saying why in a few words. Each
  description states the consequence (« plus simple, mais … »). The user can always pick « Autre »:
  don't add one.
- `multiSelect: true` when several answers can hold together (« lesquels garder ? »).
- `preview` when comparing things to look at: code, config, layout, message wording.
- `header`: a 12-character chip, in French (« Portée », « Stockage », « Nommage »).
- Tutoiement, short French, no jargon the user did not use first.

## 4. Rounds

After each round, use the answers: they may close questions, open new ones, or need a check
(read a file, run a read-only command) before the next round. Stop when every decision that
matters is taken, usually 1 to 3 rounds. Never ask the same thing twice; if an answer is
« Autre » and unclear, rephrase once with sharper options.

## 5. Recap

End with a short French recap:

```
**Décidé**
- <décision> — <raison courte si donnée>
**Je pars sur (par défaut)**
- <choix non demandé, réversible>
**Encore ouvert**
- <ce qui reste, ou rien>
```

Then carry on with the work those answers unblock, unless the user only wanted to think it through
or the next step is outward-facing (push, message, deploy): then ask before acting.
