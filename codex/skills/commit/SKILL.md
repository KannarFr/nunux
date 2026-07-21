---
name: commit
description: Review currently staged Git changes, generate a conventional commit message, and create the commit. Use when the user asks to commit staged work.
---

# Commit Staged Changes

1. Inspect the staged summary with `git diff --cached --stat`, then review the
   complete staged diff with `git diff --cached`.
2. If nothing is staged, stop and tell the user; do not add files implicitly.
3. Create a concise Conventional Commit message from the staged work:

   ```text
   type(scope): subject

   body
   ```

   Use `feat`, `fix`, `refactor`, `test`, `docs`, `style`, `perf`, `chore`, or
   `ci`. Keep the subject imperative, lowercase, period-free, and at most 50
   characters. Add a body only when the rationale is not obvious; wrap it at
   72 characters.
4. Commit the staged changes with `git commit -m "<subject>"` and, when needed,
   a second `-m` for the body. Report the commit result and its hash.

Do not amend, push, stage unstaged work, or change the commit contents unless
the user explicitly requests it.
