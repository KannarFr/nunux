---
name: patch-and-deploy
description: Cut a patch release of one project — bump, commit, tag, push, deploy to Clever Cloud
argument-hint: "[api|web|ocr|stt|valhalla]"
---

Cut a patch release: bump the version, commit it, tag it, push, deploy to Clever Cloud, and
verify the new build is actually serving.

`$ARGUMENTS` names the project. If it is empty, ask which one rather than guessing.

## Which layout am I in?

Look for `scripts/clever-deploy.sh` at the repo root.

- **Present → monorepo** (`/home/kannar/git/myle`: `api/ web/ mobile/ ocr/ stt/ valhalla/`). Follow
  everything below.
- **Absent → single-project repo.** The old flow still applies: version in the root `build.sbt`, a
  bare `v{version}` tag, `clever deploy` from the root. Skip the monorepo table.

## Per project (monorepo)

| Project | Version lives in | Tag | Deploy |
|---|---|---|---|
| `api` | `api/build.sbt` — the `version := "x.y.z"` line | `api/vX.Y.Z` | `./scripts/clever-deploy.sh api` |
| `web` | `web/package.json` — `npm version --no-git-tag-version X.Y.Z` from `web/` | `web/vX.Y.Z` | `./scripts/clever-deploy.sh web` |
| `ocr` | *no version file* — the tag IS the version | `ocr/vX.Y.Z` | `./scripts/clever-deploy.sh ocr` |
| `stt` | *no version file* | `stt/vX.Y.Z` | `./scripts/clever-deploy.sh stt` |
| `valhalla` | *no version file* | `valhalla/vX.Y.Z` | `./scripts/clever-deploy.sh valhalla` |

**`mobile` is not in this list.** It ships through EAS, not Clever — use `/patch` or
`/patch-and-eas-deploy`, which live in `mobile/.claude/skills/`.

## Steps

1. **Check the tree is clean, and that you are on `main`.** `git status --short` and
   `git rev-parse --abbrev-ref HEAD`. Anything uncommitted that is not the version bump you are
   about to make: stop and show the user. Several Claude sessions run on this repo at once — files
   you did not touch may belong to another session, so never `git add -A`. If `HEAD` is not `main`,
   stop and ask: every step below assumes the release lands on the default branch.

2. **Read the current version from the FILE**, not from the tag list. `ocr`/`stt`/`valhalla` have no
   file, so for those take the highest `<project>/v*` tag —
   `git tag --list '<project>/v*' --sort=-v:refname | head -1` — then sanity-check it looks like
   that project's own numbering. **If that command prints nothing, the project has never been
   tagged** (`stt` is in exactly this state today: 0 tags). Do not invent a number and do not fall
   back to another project's — propose `v0.1.0`, explain that it is the first tag, and get the
   user's confirmation before continuing. A wrong first tag is permanent: it becomes the "highest
   tag" that every future release of that project reads back.

3. **Bump the patch** (1.26.24 → 1.26.25) and show the user `old → new` before committing.

4. **Commit** — the bump is its own commit, nothing else in it:
   ```
   git add <version file>
   git commit -m "chore: bump version to {new_version}"
   ```
   For a project with no version file there is nothing to commit; tag the current `HEAD`.

5. **Tag locally** — do not push it yet (step 9 does, after the deploy is verified):
   ```
   git tag <project>/v{new_version}
   ```

6. **Push the commit** (not the tag):
   ```
   git push origin HEAD
   ```
   `HEAD`, not a hardcoded `main`: pushing a branch name you are not on publishes a stale branch
   while the release commit stays local, and the deploy in step 7 splits from local `HEAD`.
   For a project with no version file this is a no-op — there is nothing new to push.

7. **Deploy**:
   ```
   ./scripts/clever-deploy.sh <project> --dry-run   # split + negotiate, deploy nothing
   ./scripts/clever-deploy.sh <project>             # asks before pushing = production
   ```
   The split walks the whole history (~30 s) — it is not hung. The script refuses to run with
   uncommitted changes under the project and checks the split's tree matches `HEAD:<project>`
   before pushing.

   **If the push reports `Everything up-to-date`, no build was triggered.** On the file-less
   projects step 4 commits nothing, so when no code under `<project>/` has changed since the last
   deploy the subtree split resolves to the same SHA and the force-push is a no-op. Clever starts
   nothing, no version will ever flip, and step 8 would poll forever. Stop and say so.

8. **Verify it actually flipped.** A queued redeploy is not a live one, and a build that fails
   leaves the OLD version serving — silently. Poll for something only the new build can answer
   (a field the new code returns, a changed asset hash) until it appears, and say so explicitly.
   `curl` a health route in a bounded loop; do not declare success on the push message alone.

9. **Push the tag, last.** Only once step 8 has confirmed the new build is serving:
   ```
   git tag --points-at HEAD          # confirm it is the commit you deployed
   git push origin <project>/v{new_version}
   ```
   The tag goes last because `clever-deploy.sh` exits non-zero on a declined prompt or a
   split-tree mismatch. Push it earlier and any abort leaves a public tag for a release that
   never shipped. If the deploy did fail, delete the local tag (`git tag -d <project>/vX.Y.Z`)
   before retrying.

## Traps this repo has already sprung

- **Never a bare `vX.Y.Z` tag.** Every tag in this repo is namespaced by project; a bare one is
  ambiguous and the deploy scripts and release tooling cannot place it. Do not try to check for
  one with `git tag --list 'v*'` — git's wildmatch lets `*` cross `/`, so that pattern also
  matches every `valhalla/v*` tag and looks like a hit. Use `git tag | grep '^v[0-9]'`.
- **`clever deploy` does not work here.** Clever expects a repo whose *root* is the app; the
  monorepo is pushed as a subtree split. That is the whole point of the script.
- **The highest tag is not the current version.** A stray `api/v2.78.5` (web numbering on an api
  prefix, from the 2026-08-30 import) outranks every real `api/v1.x` under `--sort=-v:refname`.
  For `api` and `web` the version file settles it. **`ocr`/`stt`/`valhalla` have no version file,
  so they have no such check** — the same bad import that produced `api/v2.78.5` would silently
  set their release number with nothing to contradict it. For those three, show the user the full
  `git tag --list '<project>/v*' --sort=-v:refname` list, not just the top entry, and have them
  confirm the number before you tag.
- **Order across projects: api first, then web, then mobile.** Flyway migrations run at API
  startup, and a web build gated on rights or routes the deployed API does not have yet is a
  regression the moment it goes live. A store release takes days, so mobile is grouped and last.
- **Deploying `api` applies every pending migration.** Check what is new under
  `api/conf/db/migration/` before pushing, and say which ones will run.

## Always

- Show `old → new` before committing.
- If a step fails, stop and report it — never continue past a failure.
- Never push a tag you have not verified points at the commit you deployed
  (`git tag --points-at HEAD`).
