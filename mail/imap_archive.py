#!/usr/bin/env python3
"""Archive a password IMAP account's old mail (OVH, Orange…) into the archive, like gmail_archive.py.

    imap_archive.py <account> <cutoff> plan|local|fetch|verify|spotcheck [n]|trash|status

    account  an `imap.<address>` line of the settings file; cutoff like 09-Sep-2026.

Passwords come from the settings file (see store.py), never printed. Same phases as the Gmail
tool, per folder; Drafts, Trash, Junk and Templates are left alone. `trash` moves the verified messages
to the account's Trash folder: the server does not empty it by itself.
Each archived message carries X-Archive-Folder (where it was) and X-Archive-UID.
"""
import datetime, imaplib, mmap, os, random, re, sqlite3, sys, time
import gmail_archive as ga
import store

ARCHIVE = ga.ARCHIVE
PASSWORDS = store.CONFIG  # account=password lines, chmod 600
ACCOUNTS = {a: dict(zip(("host", "tb", "trash"), v.split("|"))) for a, v in store.accounts("imap").items()}
SKIP = re.compile(r"(?i)(^|[/.])(trash|corbeille|drafts?|brouillons?|junk|spam|templates?|ind[ée]sirables?|QUARANTAINE)([/.]|$)")


def password(account):
    """The account's password, or None when it has no line in the settings file."""
    return store.config(account)


def connect(account):
    pw = password(account)
    if pw is None:
        sys.exit(f"no password for {account} in {PASSWORDS}")
    m = imaplib.IMAP4_SSL(ACCOUNTS[account]["host"], timeout=180)
    m.login(account, pw)
    return m


def folders(m):
    out = []
    for b in m.list()[1]:
        mt = re.match(r'\((.*?)\) (?:"(.)"|NIL) (.*)', b.decode())
        if not mt:
            continue
        flags, _, name = mt.groups()
        out.append((flags, name))
    return out


def db_open(account):
    d = os.path.join(ARCHIVE, account)
    os.makedirs(d, exist_ok=True)
    db = sqlite3.connect(os.path.join(d, "index.sqlite"))
    db.executescript("""
        create table if not exists folders(name text primary key, uidvalidity integer);
        create table if not exists msgs(
            folder text, uid integer, size integer, internaldate text, message_id text,
            state text, source text, file text, offset integer, length integer, verified integer default 0,
            primary key(folder, uid));
        create index if not exists msgs_state on msgs(state);
    """)
    return db, d


def select(m, name, readonly=True):
    typ, d = m.select(name, readonly=readonly)
    if typ != "OK":
        return None
    return int(m.response("UIDVALIDITY")[1][0])


def plan(account, cutoff):
    db, _ = db_open(account)
    m = connect(account)
    for flags, name in folders(m):
        bare = name.strip('"')
        if "\\Noselect" in flags or SKIP.search(bare) or re.search(r"\\(Trash|Drafts|Junk)", flags):
            print(f"  (left alone) {name}")
            continue
        uv = select(m, name)
        if uv is None:
            print(f"  cannot select {name}")
            continue
        old = db.execute("select uidvalidity from folders where name=?", (name,)).fetchone()
        if old and old[0] != uv:
            sys.exit(f"UIDVALIDITY changed on {name}")
        db.execute("insert or replace into folders values(?,?)", (name, uv))
        uids = sorted(int(u) for u in m.uid("SEARCH", "BEFORE", cutoff)[1][0].split())
        known = {r[0] for r in db.execute("select uid from msgs where folder=?", (name,))}
        todo = [u for u in uids if u not in known]
        for i in range(0, len(todo), 1000):
            typ, d = m.uid("FETCH", ga.ranges(todo[i:i + 1000]),
                           "(RFC822.SIZE INTERNALDATE BODY.PEEK[HEADER.FIELDS (MESSAGE-ID)])")
            for text, lits in ga.groups(d):
                uid = re.search(rb"UID (\d+)", text)
                size = re.search(rb"RFC822\.SIZE (\d+)", text)
                date = re.search(rb'INTERNALDATE "([^"]+)"', text)
                if not (uid and size and date):
                    continue
                mid = re.search(rb"<[^>\r\n]*>", lits[-1]) if lits else None
                db.execute("insert or ignore into msgs(folder,uid,size,internaldate,message_id,state) values(?,?,?,?,?,'planned')",
                           (name, int(uid.group(1)), int(size.group(1)), date.group(1).decode().strip(),
                            mid.group(0).decode("utf-8", "replace") if mid else None))
            db.commit()
        n = db.execute("select count(*) from msgs where folder=?", (name,)).fetchone()[0]
        if n != len(uids):
            print(f"  WARNING {name}: {len(uids)} on the server, {n} planned")
        print(f"  {len(uids):>7} old  {name}", flush=True)
    m.logout()
    status(account)


class Writer:
    def __init__(self, db, d):
        self.db, self.d, self.files, self.n = db, d, {}, 0

    def add(self, folder, uid, internaldate, raw, source):
        t = datetime.datetime.strptime(internaldate, "%d-%b-%Y %H:%M:%S %z")
        name = f"{t.year}/{store.RUN_ID}.mbox"
        f = self.files.get(name)
        if f is None:
            os.makedirs(os.path.join(self.d, str(t.year)), exist_ok=True)
            f = self.files[name] = open(os.path.join(self.d, name), "ab")
        body = re.sub(rb"(?m)^(>*From )", rb">\1", raw.replace(b"\r\n", b"\n"))
        if not body.endswith(b"\n"):
            body += b"\n"
        rec = (b"From MAILER-DAEMON " + t.astimezone(datetime.timezone.utc).strftime("%a %b %d %H:%M:%S %Y").encode()
               + b"\nX-Archive-Folder: " + folder.encode() + b"\nX-Archive-UID: " + str(uid).encode() + b"\n" + body + b"\n")
        f.seek(0, 2)
        off = f.tell()
        f.write(rec)
        self.db.execute("update msgs set state='archived', source=?, file=?, offset=?, length=? where folder=? and uid=?",
                        (source, name, off, len(rec), folder, uid))
        self.n += 1
        if self.n % 500 == 0:
            self.flush()

    def flush(self):
        for f in self.files.values():
            f.flush()
            os.fsync(f.fileno())
        self.db.commit()


def local(account):
    db, d = db_open(account)
    want = {}
    for folder, uid, size, date, mid in db.execute(
            "select folder,uid,size,internaldate,message_id from msgs where state='planned' and message_id is not null "
            "and message_id in (select message_id from msgs group by message_id having count(*)=1)"):
        want[mid] = (folder, uid, size, date)
    print(f"{len(want)} planned messages to look for on disk")
    root = os.path.join(ga.g.profile(), ACCOUNTS[account]["tb"])
    w, hit = Writer(db, d), 0
    for dirpath, _, names in os.walk(root):
        for n in sorted(names):
            p = os.path.join(dirpath, n)
            if n.endswith((".msf", ".dat", ".html", ".json")) or os.path.getsize(p) == 0:
                continue
            with open(p, "rb") as fh:
                mm = mmap.mmap(fh.fileno(), 0, access=mmap.ACCESS_READ)
                starts = [(s.start() + (0 if s.start() == 0 else 1), s.end()) for s in ga.SEP.finditer(mm)]
                before = hit
                for i, (sep, body) in enumerate(starts):
                    end = starts[i + 1][0] if i + 1 < len(starts) else len(mm)
                    head = mm[body:min(end, body + 65536)]
                    cut = head.find(b"\r\n\r\n")
                    mid = ga.MID.search(head if cut < 0 else head[:cut + 2])
                    c = want.get(mid.group(1).decode("utf-8", "replace")) if mid else None
                    if not c:
                        continue
                    fit = ga.local_fit(mm[body:end], c[2])
                    if fit is not None:
                        w.add(c[0], c[1], c[3], fit, "local")
                        del want[mid.group(1).decode("utf-8", "replace")]
                        hit += 1
                mm.close()
            print(f"  {hit - before:>7} from {os.path.relpath(p, root)}", flush=True)
    w.flush()
    status(account)


def fetch(account):
    db, d = db_open(account)
    w, m, got = Writer(db, d), connect(account), 0
    for folder, in db.execute("select distinct folder from msgs where state='planned'").fetchall():
        todo = db.execute("select uid,size,internaldate from msgs where state='planned' and folder=? order by uid", (folder,)).fetchall()
        if select(m, folder) != db.execute("select uidvalidity from folders where name=?", (folder,)).fetchone()[0]:
            sys.exit(f"UIDVALIDITY changed on {folder}")
        i = 0
        while i < len(todo):
            batch, sz = [], 0
            while i + len(batch) < len(todo) and len(batch) < 50 and sz < 20e6:
                batch.append(todo[i + len(batch)])
                sz += batch[-1][1]
            byuid = {r[0]: r for r in batch}
            for attempt in range(4):
                try:
                    typ, data = m.uid("FETCH", ga.ranges(sorted(byuid)), "(BODY.PEEK[])")
                    if typ != "OK":
                        raise imaplib.IMAP4.error(str(data))
                    break
                except (imaplib.IMAP4.error, OSError) as e:
                    print(f"  IMAP error ({e}); retry {attempt + 1}", flush=True)
                    time.sleep(15 * (attempt + 1))
                    m = connect(account)
                    select(m, folder)
            else:
                w.flush()
                sys.exit("giving up for now: rerun `fetch`")
            for text, lits in ga.groups(data):
                uid = re.search(rb"UID (\d+)", text)
                if uid and lits and int(uid.group(1)) in byuid:
                    w.add(folder, int(uid.group(1)), byuid[int(uid.group(1))][2], lits[-1], "imap")
                    got += len(lits[-1])
            i += len(batch)
        w.flush()
        print(f"  {len(todo):>7} downloaded from {folder}  (total {got / 1e9:.2f} GB)", flush=True)
    m.logout()
    status(account)


def verify(account):
    db, d = db_open(account)
    ok = bad = 0
    for folder, uid, name, off, length in db.execute(
            "select folder,uid,file,offset,length from msgs where state='archived' order by file,offset").fetchall():
        rec = store.read_record(account, name, off, length)
        good = (len(rec) == length and rec.startswith(b"From MAILER-DAEMON ") and rec.endswith(b"\n\n")
                and (b"\nX-Archive-Folder: " + folder.encode() + b"\nX-Archive-UID: " + str(uid).encode() + b"\n") in rec[:400])
        db.execute("update msgs set verified=? where folder=? and uid=?", (1 if good else 0, folder, uid))
        ok += good
        bad += not good
    db.commit()
    print(f"verified {ok} records, {bad} bad")
    status(account)
    return bad


def spotcheck(account, n):
    db, d = db_open(account)
    rows = db.execute("select folder,uid,file,offset,length,source from msgs where state='archived' order by random() limit ?", (n,)).fetchall()
    m, ok, bad, cur = connect(account), 0, 0, None
    for folder, uid, name, off, length, source in sorted(rows):
        if folder != cur:
            select(m, folder)
            cur = folder
        text, lits = next(ga.groups(m.uid("FETCH", str(uid), "(BODY.PEEK[])")[1]))
        want = re.sub(rb"(?m)^(>*From )", rb">\1", lits[-1].replace(b"\r\n", b"\n"))
        body = store.read_record(account, name, off, length).split(b"\n", 3)[3]
        same = body.rstrip(b"\n") == want.rstrip(b"\n")
        ok += same
        bad += not same
        if not same:
            print("DIFF", folder, uid, source, len(body), len(want))
    print(f"{ok} identical, {bad} different")
    return bad


def trash(account):
    db, _ = db_open(account)
    m = connect(account)
    tname = '"' + ACCOUNTS[account]["trash"] + '"'
    if select(m, tname) is None:
        sys.exit("no Trash folder " + tname)
    move = b"MOVE" in b" ".join(m.capability()[1])
    for folder, in db.execute("select distinct folder from msgs where state='archived' and verified=1").fetchall():
        rows = [r[0] for r in db.execute("select uid from msgs where state='archived' and verified=1 and folder=? order by uid", (folder,))]
        if select(m, folder, readonly=False) != db.execute("select uidvalidity from folders where name=?", (folder,)).fetchone()[0]:
            sys.exit(f"UIDVALIDITY changed on {folder}: nothing moved there")
        for i in range(0, len(rows), 100):
            chunk = rows[i:i + 100]
            rng = ga.ranges(chunk)
            for attempt in range(5):
                try:
                    if move:
                        typ, dd = m.uid("MOVE", rng, tname)
                    else:
                        typ, dd = m.uid("COPY", rng, tname)
                        if typ == "OK":
                            m.uid("STORE", rng, "+FLAGS.SILENT", "(\\Deleted)")
                            typ, dd = m.uid("EXPUNGE", rng)
                    break
                except (imaplib.IMAP4.error, OSError) as e:
                    # a chunk the server did move before hanging is simply gone from the folder on the retry
                    print(f"  IMAP error ({e}); retry {attempt + 1}", flush=True)
                    time.sleep(20 * (attempt + 1))
                    m = connect(account)
                    select(m, folder, readonly=False)
            else:
                sys.exit("giving up for now: rerun `trash`")
            if typ != "OK":
                sys.exit(f"move failed on {folder}: {dd}")
            db.executemany("update msgs set state='trashed' where folder=? and uid=?", [(folder, u) for u in chunk])
            db.commit()
            if i % 2000 == 0:
                print(f"    {folder} {i}/{len(rows)}", flush=True)
        print(f"  {len(rows):>7} moved to Trash from {folder}", flush=True)
    m.logout()
    status(account)


def status(account):
    db, _ = db_open(account)
    for state, source, n, size in db.execute(
            "select state, coalesce(source,''), count(*), sum(size) from msgs group by 1,2 order by 1,2"):
        print(f"  {state:<9} {source:<6} {n:>8} messages  {size / 1e9:6.2f} GB")
    print("  unverified archived:", db.execute("select count(*) from msgs where state='archived' and verified=0").fetchone()[0])


if __name__ == "__main__":
    account, cutoff, cmd = sys.argv[1], sys.argv[2], sys.argv[3]
    n = int(sys.argv[4]) if len(sys.argv) > 4 else 300
    {"plan": lambda: plan(account, cutoff), "local": lambda: local(account), "fetch": lambda: fetch(account),
     "verify": lambda: sys.exit(1 if verify(account) else 0), "spotcheck": lambda: sys.exit(1 if spotcheck(account, n) else 0),
     "trash": lambda: trash(account), "status": lambda: status(account)}[cmd]()
