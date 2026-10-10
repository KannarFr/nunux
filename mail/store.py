"""Where the archive lives: a small local state directory, and the NAS that holds the mail itself.

Local, ~/.local/share/mail-archive/:
    <account>/index.sqlite     one row per archived message (server id, file, offset, length)
    <account>/<year>/<run>.mbox  segments written by a run, until they are shipped
    search.sqlite, runs.jsonl

NAS, <nas>/<account>/…: every mbox segment, moved there by ship() once its checksum matches, plus a
copy of each index.sqlite and of runs.jsonl. A segment is never modified after it is shipped.

Settings come from ~/.local/share/mail-archive.env (chmod 600), `key=value` lines:
    nas=user@host:/absolute/path     over ssh (key auth); or nas=/mounted/or/local/dir
    nas_port=22                      optional
    gmail.<address>=<Thunderbird cache dir, relative to the profile>
    imap.<address>=<host>|<Thunderbird cache dir>|<Trash folder name>
    <address>=<password>             one per imap.<address>
"""
import datetime, hashlib, os, shlex, shutil, sqlite3, subprocess, sys

STATE = os.path.expanduser(os.environ.get("MAIL_ARCHIVE_STATE", "~/.local/share/mail-archive"))
CONFIG = os.path.expanduser(os.environ.get("MAIL_ARCHIVE_CONFIG", "~/.local/share/mail-archive.env"))
# One segment per run and per year: every phase of a run appends to the same files.
RUN_ID = os.environ.get("MAIL_ARCHIVE_RUN") or datetime.datetime.now().strftime("%Y%m%d-%H%M%S")


def config(key):
    try:
        for line in open(CONFIG):
            k, sep, v = line.rstrip("\n").partition("=")
            if sep and k.strip() == key and not line.startswith("#"):
                return v
    except OSError:
        pass
    return None


def accounts(kind):
    """{address: value} for the `gmail.<address>=…` or `imap.<address>=…` lines, in file order."""
    out = {}
    try:
        for line in open(CONFIG):
            k, sep, v = line.rstrip("\n").partition("=")
            if sep and k.startswith(kind + "."):
                out[k[len(kind) + 1:].strip()] = v.strip()
    except OSError:
        pass
    return out


def nas():
    """(ssh target or None, base path) of the NAS, or None when it is not configured."""
    v = (config("nas") or "").strip()
    if not v:
        return None
    if v.startswith("/"):
        return None, v.rstrip("/")
    target, _, path = v.partition(":")
    return target, path.rstrip("/")


def sh(script, stdin=None, capture=True, timeout=None):
    """Run a shell snippet where the archive is: on the NAS over ssh, or here for a mounted path."""
    target, _ = nas()
    cmd = ["sh", "-c", script] if target is None else \
        ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=20", "-o", "ServerAliveInterval=30",
         "-p", (config("nas_port") or "22").strip(), target, script]
    return subprocess.run(cmd, stdin=stdin, stdout=subprocess.PIPE if capture else None,
                          stderr=subprocess.PIPE, timeout=timeout)


def remote_path(account, name):
    return f"{nas()[1]}/{account}/{name}"


def read_record(account, name, offset, length):
    """The bytes of one record, from the local segment if it is still here, else from the NAS."""
    local = os.path.join(STATE, account, name)
    if os.path.exists(local):
        with open(local, "rb") as f:
            f.seek(offset)
            return f.read(length)
    if nas() is None:
        sys.exit(f"{local} is gone and no nas= is configured in {CONFIG}")
    r = sh(f"tail -c +{offset + 1} {shlex.quote(remote_path(account, name))} | head -c {length}", timeout=300)
    if r.returncode != 0 or len(r.stdout) != length:
        sys.exit(f"cannot read {account}/{name} from the NAS: {r.stderr.decode(errors='replace').strip()[:200]}")
    return r.stdout


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def put(local, remote):
    """Copy one file to the NAS and prove it arrived intact. Returns its sha256."""
    want, tmp = sha256(local), remote + ".part"
    q = shlex.quote
    with open(local, "rb") as f:
        # umask: the share sits in a folder other NAS accounts can list
        r = sh(f"umask 077 && mkdir -p {q(os.path.dirname(remote))} && cat > {q(tmp)}", stdin=f)
    if r.returncode != 0:
        raise OSError("upload failed: " + r.stderr.decode(errors="replace").strip()[:200])
    r = sh(f"sha256sum {q(tmp)}")
    got = r.stdout.decode(errors="replace").split()[0] if r.returncode == 0 and r.stdout.split() else None
    if got != want:
        sh(f"rm -f {q(tmp)}")
        raise OSError(f"checksum mismatch on the NAS for {remote} (got {got})")
    r = sh(f"mv -f {q(tmp)} {q(remote)}")
    if r.returncode != 0:
        raise OSError("rename failed: " + r.stderr.decode(errors="replace").strip()[:200])
    return want


def segments(account):
    """mbox segments of an account that are still on the local disk, as paths relative to its directory."""
    root, out = os.path.join(STATE, account), []
    for dirpath, _, names in os.walk(root):
        out += [os.path.relpath(os.path.join(dirpath, n), root) for n in names if n.endswith(".mbox")]
    return sorted(out)


def ship(account):
    """Move the account's local segments to the NAS, then refresh its index copy there."""
    if nas() is None:
        return {"status": "skipped", "error": "no nas= in " + CONFIG}
    root = os.path.join(STATE, account)
    db = sqlite3.connect(os.path.join(root, "index.sqlite"))
    db.execute("create table if not exists shipped(file text primary key, size integer, sha256 text, at text)")
    n = size = 0
    try:
        for name in segments(account):
            local = os.path.join(root, name)
            digest = put(local, remote_path(account, name))
            db.execute("insert or replace into shipped values(?,?,?,?)",
                       (name, os.path.getsize(local), digest, datetime.datetime.now().isoformat(timespec="seconds")))
            db.commit()  # recorded before the local copy goes
            size += os.path.getsize(local)
            os.remove(local)
            n += 1
        if n:
            snap = os.path.join(root, "index.snapshot")
            if os.path.exists(snap):
                os.remove(snap)
            dst = sqlite3.connect(snap)
            db.backup(dst)
            dst.close()
            put(snap, remote_path(account, "index.sqlite"))
            os.remove(snap)
    except (OSError, subprocess.SubprocessError) as e:
        return {"status": "failed", "error": str(e), "segments": n, "bytes": size}
    return {"status": "ok", "segments": n, "bytes": size}


def ship_file(local, name):
    if nas() is not None and os.path.exists(local):
        tmp = local + ".snapshot"
        shutil.copyfile(local, tmp)
        try:
            put(tmp, f"{nas()[1]}/{name}")
        finally:
            os.remove(tmp)
