---
name: patch-and-deploy
description: Create the next SemVer patch release and deploy it using the project's established release path. Use when the user invokes /patch-and-deploy or asks to bump a project from x.y.z to x.y.(z+1), publish a patch release, tag and push a patch version, or deploy a patch safely across package managers and CI/CD systems.
---

# Patch and Deploy

Create exactly one patch release and deploy it through the repository's existing
automation. Treat an explicit invocation as authorization for the normal
release-only changes, commit, tag, push, publish, and deployment described by
the discovered project contract. Do not broaden the change set.

## 1. Discover the release contract

Read repository instructions first. Then inspect, in this order:

1. release/deployment documentation and recent release commits/tags;
2. CI/CD workflows and release configuration;
3. package-manager scripts, task runners, and build manifests;
4. hosting or infrastructure configuration.

Determine and record:

- the authoritative version source and current stable SemVer;
- whether one tool owns bumping, committing, tagging, publishing, or deploying;
- the release branch, remote, tag prefix, and release commit convention;
- required checks and credentials;
- the deployment trigger and how success can be verified.

Prefer repository evidence over ecosystem defaults. Never run two mechanisms
that own the same release step. For example, if a release command bumps and
tags, do not bump or tag separately.

## 2. Run safety gates

Before changing anything:

- Require a Git repository with no unrelated tracked, staged, or untracked
  changes. Do not stage, stash, discard, or include pre-existing work.
- Require a named branch with the expected upstream. Fetch before deciding
  whether it is current; stop if it is behind, diverged, or not the established
  release branch.
- Resolve the current version to one authoritative stable `MAJOR.MINOR.PATCH`
  value. Stop on conflicting versions or ambiguous prerelease/build metadata.
- Compute only `MAJOR.MINOR.(PATCH + 1)`. Never change major or minor.
- Ensure the target version and inferred tag do not already exist locally or
  remotely.
- Check required tools and authentication without printing secrets.
- Run the project's established pre-release checks before bumping.

Stop and ask one focused question only when project evidence cannot resolve a
material choice such as release branch, version source, deploy target, or
multiple plausible deployment mechanisms. Do not invent release infrastructure.

## 3. Create the patch release

If an established all-in-one patch-release command exists, use it with the
smallest option that selects a patch release and let it own its documented
steps. Otherwise:

1. Update the authoritative version with the project's native version command
   when possible, without letting it commit or tag implicitly.
2. Refresh only lockfiles or generated metadata that the normal version command
   updates.
3. Update a changelog only when the repository's release convention requires
   it; derive entries from commits since the previous release.
4. Review the complete diff. It must contain only release metadata for the
   computed version.
5. Run the established checks again against the release state.
6. Create the release commit and annotated or lightweight tag using the exact
   conventions inferred from recent releases. Preserve signing conventions.

Avoid ad-hoc search-and-replace across manifests. In a monorepo, release only
the scope clearly requested or clearly governed by a single workspace version;
stop if independent package versions make the target ambiguous.

## 4. Deploy through the established path

Choose exactly one primary path, using the first path supported by repository
evidence:

1. Push the release commit and tag when CI publishes/deploys from tags.
2. Push the release commit when the release branch itself triggers deployment.
3. Run the documented release workflow or deploy task when it is explicitly
   manual.
4. Publish with the established package-manager command when publishing is the
   project's deployment mechanism.

Use non-interactive commands where supported. Never add `--force`, bypass
checks, disable signing, change environments, or substitute a production target
for an unspecified target. If no deployment path is established, stop after
local validation and explain what is missing; do not push an unusable release.

## 5. Verify and report

Verify as far as available:

- the release commit and tag point to the intended tree;
- the remote branch/tag or release exists;
- CI/CD completed successfully;
- the registry, service health/version endpoint, or hosting provider reports
  the new version.

If a remote step fails, preserve evidence and stop. Do not delete remote tags,
rewrite history, republish, or roll back production automatically.

Report the old and new versions, release commit, tag, pushed remote, deployment
mechanism and target, checks run, verification result, and any manual follow-up.
