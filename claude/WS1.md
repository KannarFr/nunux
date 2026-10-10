# ws1: remote compute for this laptop

`ws1` is a Clever Cloud workstation VM (32 cores, 62G RAM, ~460G encrypted home), reachable as `ssh ws1` (root) or `ssh kannar@ws1`. This laptop is the weak machine: it has frozen under load before. So the session on the laptop stays the advisor (talking to the user, planning, reading, small edits, reviewing results) and heavy work goes to ws1.

The helper is `/home/kannar/git/kannar/nunux/bin/ws1` (not on `$PATH`, call it by absolute path). Run it with no argument for the full usage. Everything it starts runs as the unprivileged user `kannar`.

## Rule

Before launching a subagent, a build, a test suite or anything else that will keep cores busy for more than a minute or so, run `ws1 load`.

- **`free` (exit 0): run it on ws1.**
- **`busy` (exit 1) or unreachable (exit 2): run it on the laptop** as usual, and say so in one line.

Cheap work stays local without checking: searches, reading files, short commands, and agents that only read (Explore, Plan). The point is to move CPU and RAM, not every tool call.

## Agents on ws1

`ws1 run` copies the current git tree to the same path under `/home/kannar` on ws1 and starts a headless `claude -p` there, in the same subdirectory, inside a tmux session, on the user's own Claude login.

```sh
ws1 run --wait - <<'EOF'
<the brief>
EOF
```

- Launch it as a **background** Bash command with `--wait`: it returns when the agent ends and prints its final answer, and several can run in parallel. Without `--wait` it prints the run id at once; `ws1 wait <id>` or `ws1 result <id>` reads the answer later; `ws1 ls` lists runs.
- The agent sees the working tree, uncommitted changes included, but none of this conversation: the brief must stand alone (goal, what done looks like, what is known, constraints, what to send back).
- It runs with `--permission-mode bypassPermissions`. Tell it not to push, and not to touch anything outside its directory.
- **Its edits stay on ws1 until collected**: review `ws1 diff`, then apply with `ws1 diff | git apply` from the same repo. Collect before the next `sync` or `run` of that repo, which overwrites the remote copies of the files it sends. Parallel agents on the same repo share one remote tree, so give them disjoint files or run them one after another.
- Its answer is a report, not a verified fact: check the diff here.
- Keep at most 4 agents running at once unless the user asks for more.

## Builds and tests on ws1

```sh
ws1 sync                        # copy the git tree to the same path under /home/kannar
ws1 exec 'cargo test -p foo'    # run there, in the same subdirectory
```

Only git repos can be synced. `sync` sends tracked and untracked-but-not-ignored files only, so the remote `target/` survives as a build cache and gitignored or skip-worktree files stay local; files deleted here are deleted there on the next sync. The host has cargo, node, gcc and python; it has no java, sbt or docker.

## The encrypted home

`/home/kannar` on ws1 is a LUKS volume whose only key is `~/.local/share/ws1-home.key` on this laptop. After a reboot of the VM it is locked: `ws1 load` then reports `home LOCKED`, and everything else fails because kannar cannot log in. `ws1 unlock` reopens it; do that without asking. Never run `ws1 lock` unprompted, and never print, copy or move the key file: it is the only copy, and without it the home is unrecoverable.

## Limits

- The `ws1` alias logs in as root, on a VM that also runs claude-hive with the user's GitLab bootstrap token. Do not install packages, change its configuration or touch `/data/claude-hive*` unless asked; work as kannar.
- Never copy secrets (`secrets.env`, `*.env`, tokens) to it.
