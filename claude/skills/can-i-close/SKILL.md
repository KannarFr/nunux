---
name: can-i-close
description: Answer "can I close this Claude session?" with evidence instead of from memory. Use when the user asks whether everything is released, done, merged or deployed, whether anything is still running, or whether they can close / quit / end the session ("on peut close ?", "tout est release ?", "je peux fermer ?", "still have running stuff?", "all deployed?"). Checks this session's background agents and shells, leftover processes and worktrees, git state against the remote, what production actually serves, and what is still owed, then answers yes or no first.
---

# Can I close this session?

The user wants one thing: a yes or a no they can trust, then the short list of what would be lost or
left behind. Answering from memory is how a session gets closed with an agent still writing, an sbt
still eating 4 GB, or a release announced that never flipped. So check, then answer.

Everything below is read-only except step 6. Run the independent checks in one batch.

## 1. Work this session still owes

- Any background agent or shell of this session that has not reported: say which, and what it was
  doing. A session closed under a running agent loses its report. If one is running, the answer is
  **no** unless the user says to abandon it.
- Anything the user asked for in this conversation that was neither done nor explicitly dropped.
  Re-read the requests, not your own summaries of them.
- Anything you promised to report later ("je te dis si…").

## 2. Leftover processes started by this session

List long-lived processes and attribute each one before judging it:

```bash
for p in $(pgrep -f "sbt-launch|xsbt.boot|vite|playwright|eas |gradle|metro"); do
  echo "$p $(readlink /proc/$p/cwd) $(ps -o etime= -p $p) $(ps -o args= -p $p | cut -c1-90)"
done
```

- A process whose cwd is one of this session's agent worktrees or scratchpad, or whose command line
  names this session's scratchpad, is this session's. An agent's task file under the session's
  `tasks/` directory with the same agent id confirms it.
- A process in the main checkout (`sbt run`, the Vite dev server) is the user's dev stack: never
  touch it, and say you left it.
- A process in another session's worktree is not yours: report it, do not kill it.
- Orphaned wait loops (`until ! pgrep …; do sleep N; done`) left by finished agents count too.

## 3. Git

```bash
git status --short                       # uncommitted work: whose is it?
git fetch -q origin
git rev-parse --short main origin/main   # ahead / behind
git log --oneline origin/main..main      # what is local only
git tag --points-at HEAD
git worktree list                        # release / verification worktrees left behind
git stash list
```

- Uncommitted files you did not write belong to another session: name them, leave them.
- Commits that exist only locally: say whether they are meant to stay local (another session's
  unreleased work) or are an unpushed release.
- Local tags never pushed, and tags pushed for a release that never shipped.
- Frozen worktrees under `~/builds/` created for a release or a verification: remove the ones this
  session created once the release is confirmed.

## 4. What production actually serves

"Deployed" means the new version answers, not that the push succeeded. For Myle:

```bash
curl -s https://api.myleapp.fr/v1/version
curl -s https://app.myleapp.fr/meta.json
clever activity | tail -3     # last deployments: OK / CANCELLED / FAIL
```

Compare with the version files on the released commit. A deployment marked CANCELLED means another
push replaced it: the change is not live, whatever was announced. For mobile, state which track each
build is on (TestFlight / Play internal vs the public stores), since "released" is ambiguous there.

## 5. Other sessions

If other Claude sessions work on the same repository, a close can strand a coordination: a peer
waiting for "my release is live", an agreed migration number, a "do not deploy until I say" hold.
Check the conversation for any such open promise and send the closing message before answering.

## 6. Clean up what is safely yours

Only after attribution in step 2 and 3: stop this session's orphaned processes, remove this
session's finished release/verification worktrees, delete temporary copies of production data
(logs, dumps) from the scratchpad. Say what you stopped or removed. Never delete agent worktrees
that hold unmerged branches without asking.

## 7. Memory

If the session changed durable state the next session must know (what is in production, a standing
constraint such as "never roll back below version X", a decision the user made), make sure the
project memory records it before saying yes. Do not log completed work for its own sake.

## The answer

First line: **yes** or **no**, with the one reason if no.

Then, short:
- what was verified just now (production versions, git aligned, nothing running), as facts with
  their values;
- what you stopped or removed in step 6;
- what remains, split in two: things that need this session (so the answer was no), and things
  that do not (the user's own manual steps, another session's work). The second list never blocks
  a yes;
- anything you could not check, said plainly.

Answer in the user's language. No recap of the session's history: they lived it.
