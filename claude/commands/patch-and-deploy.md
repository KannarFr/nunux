---
name: patch-and-deploy
description: Bump patch version, tag, commit and deploy to Clever Cloud
---

Bump the patch version, create a git tag, commit the release, and deploy to Clever Cloud.

Steps:

1. **Read current version** from `build.sbt` (the `version := "x.y.z"` line)
2. **Bump the patch version** (e.g. 1.6.4 → 1.6.5): edit `build.sbt` to update the version
3. **Commit** the version bump:
   ```
   git add build.sbt
   git commit -m "chore: bump version to {new_version}"
   ```
4. **Tag** the commit:
   ```
   git tag v{new_version}
   ```
5. **Push** the commit and tag:
   ```
   git push && git push origin v{new_version}
   ```
6. **Deploy** to Clever Cloud:
   ```
   clever deploy
   ```

**Important:**
- Before starting, verify there are no uncommitted changes other than what's expected (warn the user if there are)
- Show the user the version change (old → new) before committing
- If any step fails, stop and report the error — do not continue
