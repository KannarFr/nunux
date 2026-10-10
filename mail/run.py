#!/usr/bin/env python3
"""One incremental archive pass over every account, logged as one line in runs.jsonl.

    python3 mail/run.py [--days 30] [--spotcheck 25]      (what bin/mail-archive runs)

For each account: plan -> local -> fetch -> verify -> spotcheck -> trash, with the cutoff at
today minus --days. An account stops at its first failing step, so nothing is moved to Trash unless
its new records were verified on disk and a random sample matched the server. Exit code 1 if any
account failed. Password accounts with no line in the settings file are skipped.

Then the search index is refreshed from the new segments, and the segments are shipped to the NAS
(checksum-verified, then removed here). With the NAS unreachable they simply wait for the next run.
"""
import argparse, datetime, fcntl, json, os, socket, sqlite3, subprocess, sys
import gmail_archive, imap_archive, search, store

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = store.STATE
RUNS = os.path.join(DATA, "runs.jsonl")
MONTHS = "Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec".split()


def counts(account):
    """(messages, bytes) archived so far, and how many are archived but not yet moved to Trash."""
    p = os.path.join(DATA, account, "index.sqlite")
    if not os.path.exists(p):
        return 0, 0, 0, 0
    db = sqlite3.connect(p)
    n, size = db.execute("select count(*), coalesce(sum(size),0) from msgs where state in ('archived','trashed')").fetchone()
    pending = db.execute("select count(*) from msgs where state='archived'").fetchone()[0]
    planned = db.execute("select count(*) from msgs where state='planned'").fetchone()[0]
    return n, size, pending, planned


def step(script, args):
    r = subprocess.run([sys.executable, os.path.join(HERE, script), *args], capture_output=True, text=True,
                       env={**os.environ, "MAIL_ARCHIVE_RUN": store.RUN_ID})
    return r.returncode, (r.stdout + r.stderr).strip().splitlines()[-6:]


def archive(kind, account, cutoff, sample):
    if kind == "imap" and imap_archive.password(account) is None:
        return {"status": "skipped", "error": "no password in " + imap_archive.PASSWORDS}
    script = "gmail_archive.py" if kind == "gmail" else "imap_archive.py"
    n0, size0, _, _ = counts(account)
    out = {"status": "ok"}
    for name in ("plan", "local", "fetch", "verify", "spotcheck", "trash"):
        if name in ("verify", "spotcheck", "trash"):
            _, _, pending, planned = counts(account)
            if planned:
                out.update(status="failed", failed_step="fetch", error=[f"{planned} messages still not downloaded"])
                break
            if not pending:
                break  # nothing new today
        if name == "spotcheck" and kind == "gmail":
            code, tail = step("spotcheck.py", [account, str(sample)])
        elif name == "spotcheck":
            code, tail = step(script, [account, cutoff, "spotcheck", str(sample)])
        else:
            code, tail = step(script, [account, cutoff, name])
        if code != 0 or (name == "spotcheck" and not any(" identical, 0 different" in l for l in tail)):
            out.update(status="failed", failed_step=name, error=tail)
            break
    n1, size1, pending, _ = counts(account)
    out.update(archived=n1 - n0, bytes=size1 - size0, total=n1, not_trashed=pending)
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--days", type=int, default=30, help="archive what is older than this many days (default 30)")
    ap.add_argument("--spotcheck", type=int, default=25, help="records compared with the server per account (default 25)")
    a = ap.parse_args()
    os.makedirs(DATA, exist_ok=True)
    lock = open(os.path.join(DATA, ".lock"), "w")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        sys.exit("another archive run is in progress")
    day = datetime.date.today() - datetime.timedelta(days=a.days)
    cutoff = f"{day.day:02d}-{MONTHS[day.month - 1]}-{day.year}"
    run = {"started": datetime.datetime.now().astimezone().isoformat(timespec="seconds"), "host": socket.gethostname(),
           "cutoff": day.isoformat(), "accounts": {}}
    for kind, accounts in (("gmail", gmail_archive.TB_DIRS), ("imap", imap_archive.ACCOUNTS)):
        for account in accounts:
            print(f"== {account}", flush=True)
            try:
                res = archive(kind, account, cutoff, a.spotcheck)
            except Exception as e:  # a crash in one account must not lose the run record
                res = {"status": "failed", "failed_step": "run.py", "error": [repr(e)]}
            run["accounts"][account] = res
            print("  ", json.dumps(res, ensure_ascii=False), flush=True)
    try:
        search.index()  # needs the new segments while they are still on this disk
    except Exception as e:
        run["index_error"] = repr(e)
        print("search index failed:", e, flush=True)
    else:
        for account in run["accounts"]:
            if os.path.exists(os.path.join(DATA, account, "index.sqlite")):
                run["accounts"][account]["ship"] = store.ship(account)
                print(f"== ship {account}", json.dumps(run["accounts"][account]["ship"]), flush=True)
    run["finished"] = datetime.datetime.now().astimezone().isoformat(timespec="seconds")
    states = {r["status"] for r in run["accounts"].values()} | \
             {r.get("ship", {}).get("status") for r in run["accounts"].values()}
    run["status"] = "failed" if "failed" in states else "ok"
    with open(RUNS, "a") as f:
        f.write(json.dumps(run, ensure_ascii=False) + "\n")
    try:
        store.ship_file(RUNS, "runs.jsonl")
    except Exception as e:
        print("could not copy runs.jsonl to the NAS:", e, flush=True)
    sys.exit(1 if run["status"] == "failed" else 0)


if __name__ == "__main__":
    main()
