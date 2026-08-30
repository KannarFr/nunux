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

1. **Check the tree is clean.** `git status --short`. Anything uncommitted that is not the version
   bump you are about to make: stop and show the user. Several Claude sessions run on this repo at
   once — files you did not touch may belong to another session, so never `git add -A`.

2. **Read the current version from the FILE**, not from the tag list. `ocr`/`stt`/`valhalla` have no
   file, so for those take the highest `<project>/v*` tag — and read it with
   `git tag --list '<project>/v*' --sort=-v:refname | head -1`, then sanity-check it looks like that
   project's own numbering.

3. **Bump the patch** (1.26.24 → 1.26.25) and show the user `old → new` before committing.

4. **Commit** — the bump is its own commit, nothing else in it:
   ```
   git add <version file>
   git commit -m "chore: bump version to {new_version}"
   ```
   For a project with no version file there is nothing to commit; tag the current `HEAD`.

5. **Tag with the project prefix**:
   ```
   git tag <project>/v{new_version}
   ```

6. **Push** the commit and the tag:
   ```
   git push origin main && git push origin <project>/v{new_version}
   ```

7. **Deploy**:
   ```
   ./scripts/clever-deploy.sh <project> --dry-run   # split + negotiate, deploy nothing
   ./scripts/clever-deploy.sh <project>             # asks before pushing = production
   ```
   The split walks the whole history (~30 s) — it is not hung. The script refuses to run with
   uncommitted changes under the project and checks the split's tree matches `HEAD:<project>`
   before pushing.

8. **Verify it actually flipped.** A queued redeploy is not a live one, and a build that fails
   leaves the OLD version serving — silently. Poll for something only the new build can answer
   (a field the new code returns, a changed asset hash) until it appears, and say so explicitly.
   `curl` a health route in a bounded loop; do not declare success on the push message alone.

## Traps this repo has already sprung

- **Never a bare `vX.Y.Z` tag.** 996 tags are namespaced by project; a bare one is ambiguous and
  the deploy scripts and release tooling cannot place it.
- **`clever deploy` does not work here.** Clever expects a repo whose *root* is the app; the
  monorepo is pushed as a subtree split. That is the whole point of the script.
- **The highest tag is not the current version.** A stray `api/v2.78.5` (web numbering on an api
  prefix, from the 2026-08-30 import) outranks every real `api/v1.x` under `--sort=-v:refname`.
  The version file is the source of truth.
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
