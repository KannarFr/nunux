#!/usr/bin/env python3
"""Search the mail archive. The index is local, so searching works without the NAS; only reading a
message (show) or a regex scan (grep) fetches from it.

    mail-search find WORDS… [options]    sender, recipients, subject and folder; newest first
    mail-search text WORDS… [options]    words anywhere in the subject or the body
    mail-search grep REGEX [options]     POSIX extended regex, case-insensitive, over the raw
                                         messages on the NAS (slow)
    mail-search show ID [--raw]          print one message; --raw gives the .eml
    mail-search index                    index what was archived since the last time

`find` takes SQLite FTS5 syntax: words are ANDed, "quoted phrase", prefix*, OR, NOT, and a column
filter such as sender:orange or subject:"mise en demeure" (columns: sender, recipients, subject,
folder). `text` takes words, prefix* and OR/NOT, but no phrases. `grep` sees the bytes as sent, so
base64 or quoted-printable text only matches where it is readable. IDs are the first column.
"""
import argparse, datetime, email, email.header, email.policy, os, re, shlex, sqlite3, subprocess, sys
import store

DATA = store.STATE
DB = os.path.join(DATA, "search.sqlite")
BODY_LIMIT = 200_000  # characters of body text indexed per message


def db_open():
    db = sqlite3.connect(DB)
    db.executescript("""
        create table if not exists rec(id integer primary key, account text, file text, offset integer,
                                       length integer, date text, unique(account, file, offset));
        create virtual table if not exists fts using fts5(sender, recipients, subject, folder,
                                                          tokenize='unicode61 remove_diacritics 2');
        create virtual table if not exists body using fts5(text, content='', detail=none,
                                                           tokenize='unicode61 remove_diacritics 2');
        create table if not exists body_done(id integer primary key);
    """)
    return db


def header(msg, name):
    out = []
    for v in msg.get_all(name, []):
        try:
            out.append(str(email.header.make_header(email.header.decode_header(str(v)))))
        except Exception:
            out.append(str(v))
    return " ".join(" ".join(out).split())


def iso(internaldate):
    return datetime.datetime.strptime(internaldate, "%d-%b-%Y %H:%M:%S %z").astimezone(datetime.timezone.utc).strftime("%Y-%m-%d %H:%M")


def unwrap(rec):
    """An archive record -> the message as it was on the server side (LF line endings)."""
    return re.sub(rb"(?m)^>(>*From )", rb"\1", rec[rec.index(b"\n") + 1:])


def body_text(raw):
    try:
        msg = email.message_from_bytes(raw, policy=email.policy.default)
        part = msg.get_body(preferencelist=("plain", "html"))
        text = part.get_content() if part else ""
        if part and part.get_content_type() == "text/html":
            text = re.sub(r"(?is)<(script|style).*?</\1>", " ", text)
            text = re.sub(r"(?s)<[^>]+>", " ", text)
        return (str(msg["Subject"] or "") + "\n" + text)[:BODY_LIMIT]
    except Exception:
        return ""


class Reader:
    """Sequential reads of records: straight from the local segment while it is here, else from the NAS."""

    def __init__(self):
        self.files = {}

    def read(self, account, name, off, length):
        key = (account, name)
        if key not in self.files:
            p = os.path.join(DATA, account, name)
            self.files[key] = open(p, "rb") if os.path.exists(p) else None
        f = self.files[key]
        if f is None:
            return store.read_record(account, name, off, length)
        f.seek(off)
        return f.read(length)


def index():
    db, reader, added, bodies = db_open(), Reader(), 0, 0
    for account in sorted(os.listdir(DATA)):
        src = os.path.join(DATA, account, "index.sqlite")
        if not os.path.exists(src):
            continue
        known = {(f, o) for f, o in db.execute("select file, offset from rec where account=?", (account,))}
        rows = sqlite3.connect(src).execute(
            "select file, offset, length, internaldate from msgs where file is not null order by file, offset").fetchall()
        for name, off, length, date in rows:
            if (name, off) in known:
                continue
            raw = unwrap(reader.read(account, name, off, length))
            msg = email.message_from_bytes(raw.split(b"\n\n", 1)[0])
            folder = header(msg, "X-Gmail-Labels") or header(msg, "X-Archive-Folder")
            cur = db.execute("insert into rec(account,file,offset,length,date) values(?,?,?,?,?)",
                             (account, name, off, length, iso(date)))
            db.execute("insert into fts(rowid,sender,recipients,subject,folder) values(?,?,?,?,?)",
                       (cur.lastrowid, header(msg, "From"), header(msg, "To") + " " + header(msg, "Cc"),
                        header(msg, "Subject"), folder.replace('"', " ").replace("\\", " ")))
            added += 1
            if added % 20000 == 0:
                db.commit()
                print(f"  {added} headers indexed…", flush=True)
        db.commit()
    # Bodies second, so a first big pass can be interrupted and resumed.
    todo = db.execute("select id, account, file, offset, length from rec where id not in (select id from body_done) "
                      "order by account, file, offset").fetchall()
    for i, account, name, off, length in todo:
        db.execute("insert into body(rowid, text) values(?,?)", (i, body_text(unwrap(reader.read(account, name, off, length)))))
        db.execute("insert into body_done values(?)", (i,))
        bodies += 1
        if bodies % 5000 == 0:
            db.commit()
            print(f"  {bodies}/{len(todo)} bodies indexed…", flush=True)
    db.commit()
    print(f"{added} messages added ({bodies} bodies), {db.execute('select count(*) from rec').fetchone()[0]} in the search index")


def show_rows(db, ids, limit):
    for i in ids[:limit]:
        r = db.execute("select rec.id, date, account, sender, subject from rec join fts on fts.rowid=rec.id where rec.id=?", (i,)).fetchone()
        if r:
            print(f"{r[0]:>7}  {r[1]}  {r[2].split('@')[1].split('.')[0][:13]:<13}  {r[3][:38]:<38}  {r[4][:90]}")
    if len(ids) > limit:
        print(f"… {len(ids) - limit} more (raise -n)")


def where(a):
    cond, args = [], []
    if a.account:
        cond.append("account like ?"); args.append(f"%{a.account}%")
    if a.since:
        cond.append("date >= ?"); args.append(a.since)
    if a.until:
        cond.append("date < ?"); args.append(a.until)
    return ("".join(" and " + c for c in cond), args)


def find(a, table="fts"):
    db = db_open()
    w, args = where(a)
    try:
        ids = [r[0] for r in db.execute(
            f"select rec.id from {table} join rec on rec.id={table}.rowid where {table} match ?" + w + " order by date desc",
            [" ".join(a.words)] + args)]
    except sqlite3.OperationalError as e:
        sys.exit(f"bad query ({e}); quote special characters, e.g. '\"a.b@c.fr\"'")
    show_rows(db, ids, a.n)


# Prints "<file>\t<key>" once per matching message; the key is the record's own id header
# (X-GM-MSGID, or X-Archive-Folder + X-Archive-UID). awk because the NAS only has BusyBox grep.
AWK = r"""/^X-GM-MSGID: /{k=$2} /^X-Archive-Folder: /{f=substr($0,19)} /^X-Archive-UID: /{k=f "\t" $2}
tolower($0) ~ ENVIRON["RE"] && k!="" && k!=last {print ENVIRON["FN"] "\t" k; last=k}"""


def grep(a):
    db = db_open()
    w, args = where(a)
    q, ids, seen = shlex.quote, [], set()
    for account in sorted(os.listdir(DATA)):
        d = os.path.join(DATA, account)
        if not os.path.exists(os.path.join(d, "index.sqlite")) or (a.account and a.account not in account):
            continue
        idx = sqlite3.connect(os.path.join(d, "index.sqlite"))
        gmail = any(r[1] == "gm_msgid" for r in idx.execute("pragma table_info(msgs)"))
        local = set(store.segments(account))
        remote = []
        if idx.execute("select 1 from sqlite_master where name='shipped'").fetchone():
            remote = [r[0] for r in idx.execute("select file from shipped") if r[0] not in local]

        def scan(names, path, run):
            script = "; ".join(f"LC_ALL=C RE={q(a.regex.lower())} FN={q(n)} awk {q(AWK)} {q(path(n))}" for n in names)
            return run(script).stdout.decode("utf-8", "replace").splitlines() if names else []

        lines = scan(sorted(local), lambda n: os.path.join(d, n),
                     lambda s: subprocess.run(["sh", "-c", s], capture_output=True))
        if remote and store.nas() is not None:
            lines += scan(remote, lambda n: store.remote_path(account, n), store.sh)
        for line in lines:
            name, _, key = line.partition("\t")
            if gmail:
                r = idx.execute("select file, offset from msgs where gm_msgid=?", (key,)).fetchone()
            else:
                folder, _, uid = key.rpartition("\t")
                r = idx.execute("select file, offset from msgs where folder=? and uid=?", (folder, uid)).fetchone()
            if not r:
                continue
            hit = db.execute("select id from rec where account=? and file=? and offset=?" + w, [account, r[0], r[1]] + args).fetchone()
            if hit and hit[0] not in seen:
                seen.add(hit[0])
                ids.append(hit[0])
    ids.sort(key=lambda i: db.execute("select date from rec where id=?", (i,)).fetchone()[0], reverse=True)
    show_rows(db, ids, a.n)


def show(a):
    db = db_open()
    r = db.execute("select account, file, offset, length from rec where id=?", (a.id,)).fetchone()
    if not r:
        sys.exit("no such id (run `mail-search index` first?)")
    raw = unwrap(store.read_record(*r))
    if a.raw:
        sys.stdout.buffer.write(raw)
        return
    msg = email.message_from_bytes(raw, policy=email.policy.default)
    for h in ("Date", "From", "To", "Cc", "Subject", "X-Gmail-Labels", "X-Archive-Folder"):
        if msg[h]:
            print(f"{h}: {msg[h]}")
    names = [p.get_filename() for p in msg.walk() if p.get_filename()]
    if names:
        print("Attachments:", ", ".join(names))
    print()
    body = msg.get_body(preferencelist=("plain", "html"))
    text = body.get_content() if body else ""
    if body and body.get_content_type() == "text/html":
        text = re.sub(r"(?is)<(script|style).*?</\1>", "", text)
        text = re.sub(r"(?s)<[^>]+>", " ", text)
        text = re.sub(r"[ \t]+", " ", re.sub(r"\n\s*\n+", "\n\n", text))
    print(text.strip())


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("index")
    for name in ("find", "text", "grep"):
        p = sub.add_parser(name)
        p.add_argument("regex" if name == "grep" else "words", **({} if name == "grep" else {"nargs": "+"}))
        p.add_argument("-a", "--account", help="part of the account address")
        p.add_argument("--since", help="YYYY-MM-DD")
        p.add_argument("--until", help="YYYY-MM-DD")
        p.add_argument("-n", type=int, default=40, help="rows to print (default 40)")
    p = sub.add_parser("show")
    p.add_argument("id", type=int)
    p.add_argument("--raw", action="store_true")
    a = ap.parse_args()
    {"index": index, "find": lambda: find(a), "text": lambda: find(a, "body"), "grep": lambda: grep(a),
     "show": lambda: show(a)}[a.cmd]()
