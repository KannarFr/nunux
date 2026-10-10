# ws1: remote compute for this laptop

`ws1` is a Clever Cloud workstation VM (32 cores, 62G RAM, 470G on `/data`), reachable as `ssh ws1`. This laptop is the weak machine: it has frozen under load before. So the session on the laptop stays the advisor (talking to the user, planning, reading, small edits, reviewing results) and heavy work goes to ws1.

The helper is `/home/kannar/git/kannar/nunux/bin/ws1` (not on `$PATH`, call it by absolute path). Run it with no argument for the full usage.

## Rule

Before launching a subagent, a build, a test suite or anything else that will keep cores busy for more than a minute or so, run `ws1 load`.

- **`free` (exit 0): run it on ws1.**
- **`busy` (exit 1) or unreachable (exit 2): run it on the laptop** as usual, and say so in one line.

Cheap work stays local without checking: searches, reading files, short commands, and agents that only read (Explore, Plan). The point is to move CPU and RAM, not every tool call.

## Agents on ws1

`ws1 run` spawns a headless Claude session in a container, through claude-hive.

```sh
ws1 run --repo clever-cloud/axo --name "kv watch fix" --wait - <<'EOF'
<the brief>
EOF
```

- Launch it as a **background** Bash command with `--wait`: it returns when the brief ends and prints the session's final answer, and several can run in parallel. Without `--wait` it prints the session name at once; `ws1 wait <session>` or `ws1 result <session>` reads the answer later.
- **The session sees only what is on GitLab.** It clones `--repo` fresh on its own branch `claude/<session id>` (or `--branch`), and can push and open merge requests as the user. It has none of this conversation and none of the laptop's uncommitted changes, so the brief must stand alone: goal, what done looks like, what is already known, constraints, and what to send back. Push the branch it should start from first, or use `sync` + `exec` below.
- `--repo` must be on the host's allow list (`ssh ws1 grep -A3 '^\[repos\]' .config/claude-hive/config.toml`). Without `--repo` the session is blank: no clone, no GitLab token, fine for pure research or computation.
- For code work, ask the session to push its branch and reply with the branch name and a summary. Then `git fetch` and review it here. Its answer is a report, not a verified fact.
- **Kill the session once its result is collected**: `ws1 kill <session>`. A finished session otherwise stays up as an idle interactive Claude. `ws1 ls` marks the ones spawned from this laptop with `*`; never kill the others, the user started them by hand.
- Sessions run on a Claude subscription lent by a colleague through the team registry. Keep at most 4 running at once unless the user asks for more, and do not use them for trivia.

## Builds and tests on ws1

For uncommitted work, or a repo that is not on the Clever GitLab:

```sh
ws1 sync                        # copy the git tree to the same path under /home/kannar
ws1 exec 'cargo test -p foo'    # run there as kannar, in the same subdirectory
```

`sync` sends tracked and untracked-but-not-ignored files only, so the remote `target/` survives as a build cache and gitignored or skip-worktree files stay local; files deleted here are deleted there on the next sync. The host has cargo, node, gcc and python; it has no java, sbt or docker. Results stay on ws1: copy back only what is needed (`scp kannar@ws1:...`).

## The encrypted home

`/home/kannar` on ws1 is a LUKS volume whose only key is `~/.local/share/ws1-home.key` on this laptop. After a reboot of the VM it is locked: `ws1 load` then reports `home LOCKED`, and `sync`/`exec` fail because kannar cannot log in. `ws1 unlock` reopens it; do that without asking. Never run `ws1 lock` unprompted, and never print, copy or move the key file: it is the only copy, and without it the home is unrecoverable.

Hive sessions do not live in that home. Their clones sit in podman storage under `/data/podman`, which is not encrypted.

## Limits

- The `ws1` alias logs in as root, on a VM that also holds the user's GitLab bootstrap token. Do not install packages, change its configuration or touch `/data/claude-hive*` unless asked.
- Never copy secrets (`secrets.env`, `*.env`, tokens) to it.
