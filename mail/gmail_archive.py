#!/usr/bin/env python3
"""Archive a Gmail account's old mail out of Gmail, into the archive (see store.py; mbox segments Thunderbird never opens).

    python3 mail/gmail_archive.py <account> <cutoff> plan|local|fetch|verify|trash|status

    cutoff  IMAP date, e.g. 09-Sep-2026: everything received before it is archived.

Phases, each resumable (state lives in <archive>/<account>/index.sqlite):
  plan    list every message of "All Mail" older than the cutoff (drafts are left alone)
  local   copy the ones Thunderbird already holds on disk, when the local copy is byte-exact
  fetch   download the rest over IMAP (Gmail caps IMAP downloads at ~2.5 GB/day: rerun it)
  verify  re-read every archived record from disk
  trash   move the verified messages to Gmail's Trash (Gmail purges it 30 days later)

Records are mboxrd (LF), each message carrying X-GM-MSGID and
X-Gmail-Labels like a Google Takeout export. Auth is Thunderbird's saved OAuth token.
"""
import datetime, email.utils, glob, imaplib, mmap, os, re, sqlite3, sys, time

import store
import thunderbird_oauth as g

imaplib._MAXLINE = 200_000_000
ARCHIVE = store.STATE
TB_DIRS = store.accounts("gmail")  # address -> Thunderbird's local store for that account


def connect(account):
    g.ACCOUNT = account
    tok = g.access_token()
    m = imaplib.IMAP4_SSL("imap.gmail.com")
    m.authenticate("XOAUTH2", lambda _: f"user={account}\x01auth=Bearer {tok}\x01\x01".encode())
    return m


def all_mail(m, readonly=True):
    typ, boxes = m.list()
    for b in boxes:
        flags, name = re.match(r'\((.*?)\) "/" (.*)', b.decode()).groups()
        if "\\All" in flags:
            typ, _ = m.select(name, readonly=readonly)
            if typ != "OK":
                sys.exit("cannot select " + name)
            return int(m.response("UIDVALIDITY")[1][0])
    sys.exit("no \\All folder")


def groups(data):
    """imaplib FETCH data -> one (text, [literals]) per message."""
    text, lits = b"", []
    for x in data:
        if isinstance(x, tuple):
            text += x[0]
            lits.append(x[1])
        elif x is not None:
            yield text + x, lits
            text, lits = b"", []


def ranges(uids):
    """[1,2,3,7] -> '1:3,7' (uids sorted)."""
    out, start, prev = [], None, None
    for u in uids:
        if start is None:
            start = prev = u
        elif u == prev + 1:
            prev = u
        else:
            out.append(f"{start}:{prev}" if prev > start else str(start))
            start = prev = u
    if start is not None:
        out.append(f"{start}:{prev}" if prev > start else str(start))
    return ",".join(out)


def db_open(account):
    d = os.path.join(ARCHIVE, account)
    os.makedirs(d, exist_ok=True)
    db = sqlite3.connect(os.path.join(d, "index.sqlite"))
    db.executescript("""
        create table if not exists meta(k text primary key, v text);
        create table if not exists msgs(
            gm_msgid text primary key, uid integer, size integer, internaldate text,
            labels text, message_id text, state text, source text,
            file text, offset integer, length integer, verified integer default 0);
        create index if not exists msgs_state on msgs(state);
    """)
    return db, d


def plan(account, cutoff):
    db, _ = db_open(account)
    m = connect(account)
    uidvalidity = all_mail(m)
    old = db.execute("select v from meta where k='uidvalidity'").fetchone()
    if old and int(old[0]) != uidvalidity:
        sys.exit("UIDVALIDITY changed: the plan in index.sqlite no longer matches the mailbox")
    db.execute("insert or replace into meta values('uidvalidity', ?)", (uidvalidity,))
    db.execute("insert or replace into meta values('cutoff', ?)", (cutoff,))
    typ, d = m.uid("SEARCH", "BEFORE", cutoff)
    uids = sorted(int(u) for u in d[0].split())
    known = {r[0] for r in db.execute("select uid from msgs")}
    todo = [u for u in uids if u not in known]
    print(f"{len(uids)} messages before {cutoff}, {len(todo)} new to plan")
    for i in range(0, len(todo), 2000):
        chunk = ranges(todo[i:i + 2000])
        rows = {}
        typ, d = m.uid("FETCH", chunk, "(X-GM-MSGID X-GM-LABELS RFC822.SIZE INTERNALDATE)")
        for text, lits in groups(d):
            uid = re.search(rb"UID (\d+)", text)
            gm = re.search(rb"X-GM-MSGID (\d+)", text)
            if not uid or not gm:
                continue
            size = int(re.search(rb"RFC822\.SIZE (\d+)", text).group(1))
            date = re.search(rb'INTERNALDATE "([^"]+)"', text).group(1).decode()
            lab = re.search(rb"X-GM-LABELS \((.*?)\)(?= (?:UID|RFC822\.SIZE|INTERNALDATE|X-GM-MSGID) |\)$)", text)
            labels = (lab.group(1) if lab else b"") + b" ".join(lits)
            rows[int(uid.group(1))] = [gm.group(1).decode(), size, date, labels.decode("utf-8", "replace"), None]
        typ, d = m.uid("FETCH", chunk, "(BODY.PEEK[HEADER.FIELDS (MESSAGE-ID)])")
        for text, lits in groups(d):
            uid = re.search(rb"UID (\d+)", text)
            if uid and lits and int(uid.group(1)) in rows:
                mid = re.search(rb"<[^>\r\n]*>", lits[-1])
                rows[int(uid.group(1))][4] = mid.group(0).decode("utf-8", "replace") if mid else None
        for uid, (gm, size, date, labels, mid) in rows.items():
            state = "skip" if "\\Draft" in labels else "planned"
            db.execute("insert or ignore into msgs(gm_msgid,uid,size,internaldate,labels,message_id,state) "
                       "values(?,?,?,?,?,?,?)", (gm, uid, size, date, labels, mid, state))
        db.commit()
        print(f"  planned {min(i + 2000, len(todo))}/{len(todo)}", flush=True)
    m.logout()
    status(account)


class Writer:
    """Appends records to this run's mbox segments (one per year) and remembers where each one landed."""

    def __init__(self, db, d):
        self.db, self.d, self.files, self.n = db, d, {}, 0

    def add(self, gm, internaldate, labels, raw, source):
        t = datetime.datetime.strptime(internaldate, "%d-%b-%Y %H:%M:%S %z")
        name = f"{t.year}/{store.RUN_ID}.mbox"
        f = self.files.get(name)
        if f is None:
            os.makedirs(os.path.join(self.d, str(t.year)), exist_ok=True)
            f = self.files[name] = open(os.path.join(self.d, name), "ab")
        body = raw.replace(b"\r\n", b"\n")
        body = re.sub(rb"(?m)^(>*From )", rb">\1", body)
        if not body.endswith(b"\n"):
            body += b"\n"
        rec = (b"From MAILER-DAEMON " + t.astimezone(datetime.timezone.utc).strftime("%a %b %d %H:%M:%S %Y").encode()
               + b"\nX-GM-MSGID: " + gm.encode() + b"\nX-Gmail-Labels: " + labels.encode("utf-8", "replace").replace(b"\n", b" ")
               + b"\n" + body + b"\n")
        f.seek(0, 2)
        off = f.tell()
        f.write(rec)
        self.db.execute("update msgs set state='archived', source=?, file=?, offset=?, length=? where gm_msgid=?",
                        (source, name, off, len(rec), gm))
        self.n += 1
        if self.n % 500 == 0:
            self.flush()

    def flush(self):
        for f in self.files.values():
            f.flush()
            os.fsync(f.fileno())
        self.db.commit()


SEP = re.compile(rb"(?:\A|\n)From - [^\n]*\n(?=X-Mozilla-Status)")
MID = re.compile(rb"(?im)^Message-ID:[ \t]*(?:\r?\n[ \t]+)?(<[^>\r\n]*>)")


def local_fit(raw, size):
    """The server's exact bytes from a Thunderbird mbox record, or None if it doesn't measure up."""
    while raw.startswith(b"X-Mozilla-"):
        raw = raw[raw.index(b"\n") + 1:]
    if re.search(rb"(?m)^>+From ", raw):
        return None  # Thunderbird's own From-escaping can't be told from the sender's: download it instead
    if b"\r\n" not in raw[:2000]:
        raw = raw.replace(b"\n", b"\r\n")
    if len(raw) == size or (raw[size:] in (b"\r\n", b"\n") and len(raw) > size):
        return raw[:size]
    return None


def local(account):
    db, d = db_open(account)
    want = {}
    for gm, size, date, labels, mid in db.execute(
            "select gm_msgid,size,internaldate,labels,message_id from msgs where state='planned' and message_id is not null "
            # a Message-ID delivered several times has several server copies with different headers: download those
            "and message_id in (select message_id from msgs group by message_id having count(*)=1)"):
        want.setdefault(mid, []).append((gm, size, date, labels))
    print(f"{sum(len(v) for v in want.values())} planned messages to look for on disk")
    root = os.path.join(g.profile(), TB_DIRS[account])
    w, hit = Writer(db, d), 0
    for dirpath, _, names in os.walk(root):
        for n in sorted(names):
            p = os.path.join(dirpath, n)
            if n.endswith((".msf", ".dat", ".html", ".json")) or os.path.getsize(p) == 0:
                continue
            with open(p, "rb") as fh:
                mm = mmap.mmap(fh.fileno(), 0, access=mmap.ACCESS_READ)
                starts = [(s.start() + (0 if s.start() == 0 else 1), s.end()) for s in SEP.finditer(mm)]
                before = hit
                for i, (sep, body) in enumerate(starts):
                    end = starts[i + 1][0] if i + 1 < len(starts) else len(mm)
                    head = mm[body:min(end, body + 65536)]
                    cut = head.find(b"\r\n\r\n")
                    mid = MID.search(head if cut < 0 else head[:cut + 2])
                    if not mid:
                        continue
                    cands = want.get(mid.group(1).decode("utf-8", "replace"))
                    if not cands:
                        continue
                    raw = mm[body:end]
                    for c in list(cands):
                        fit = local_fit(raw, c[1])
                        if fit is not None:
                            w.add(c[0], c[2], c[3], fit, "local")
                            cands.remove(c)
                            hit += 1
                mm.close()
            print(f"  {hit - before:>7} from {os.path.relpath(p, root)}", flush=True)
    w.flush()
    print(f"{hit} messages archived from Thunderbird's local store")
    status(account)


def fetch(account):
    db, d = db_open(account)
    todo = db.execute("select uid,gm_msgid,size,internaldate,labels from msgs where state='planned' order by uid").fetchall()
    total = sum(r[2] for r in todo)
    print(f"{len(todo)} messages to download, {total / 1e9:.2f} GB")
    w, done, got, m, t0 = Writer(db, d), 0, 0, None, time.time()
    i = 0
    while i < len(todo):
        batch, sz = [], 0
        while i + len(batch) < len(todo) and len(batch) < 100 and sz < 30e6:
            r = todo[i + len(batch)]
            batch.append(r)
            sz += r[2]
        byuid = {r[0]: r for r in batch}
        for attempt in range(4):
            try:
                if m is None or time.time() - t0 > 2700:
                    if m is not None:
                        try: m.logout()
                        except Exception: pass
                    m, t0 = connect(account), time.time()
                    all_mail(m)
                typ, data = m.uid("FETCH", ranges(sorted(byuid)), "(BODY.PEEK[])")
                if typ != "OK":
                    raise imaplib.IMAP4.error(str(data))
                break
            except (imaplib.IMAP4.error, OSError) as e:
                print(f"  IMAP error ({e}); retry {attempt + 1}", flush=True)
                m = None
                time.sleep(20 * (attempt + 1))
        else:
            w.flush()
            sys.exit("giving up for now (Gmail's daily IMAP download cap?): rerun `fetch` later")
        for text, lits in groups(data):
            uid = re.search(rb"UID (\d+)", text)
            if uid and lits and int(uid.group(1)) in byuid:
                r = byuid[int(uid.group(1))]
                w.add(r[1], r[3], r[4], lits[-1], "imap")
                done += 1
                got += len(lits[-1])
        i += len(batch)
        if (i // 100) % 20 == 0:
            print(f"  {i}/{len(todo)}  {got / 1e9:.2f} GB", flush=True)
    w.flush()
    print(f"downloaded {done} messages, {got / 1e9:.2f} GB")
    status(account)


def verify(account):
    db, d = db_open(account)
    bad = ok = 0
    for gm, name, off, length in db.execute(
            "select gm_msgid,file,offset,length from msgs where state='archived' order by file,offset").fetchall():
        rec = store.read_record(account, name, off, length)
        good = (len(rec) == length and rec.startswith(b"From MAILER-DAEMON ")
                and (b"\nX-GM-MSGID: " + gm.encode() + b"\n") in rec[:80] and rec.endswith(b"\n\n"))
        db.execute("update msgs set verified=? where gm_msgid=?", (1 if good else 0, gm))
        ok += good
        bad += not good
    db.commit()
    print(f"verified {ok} records, {bad} bad")
    status(account)
    return bad


def trash(account):
    db, _ = db_open(account)
    rows = db.execute("select uid,gm_msgid from msgs where state='archived' and verified=1 order by uid").fetchall()
    print(f"{len(rows)} verified messages to move to Gmail's Trash")
    m = connect(account)
    if all_mail(m, readonly=False) != int(db.execute("select v from meta where k='uidvalidity'").fetchone()[0]):
        sys.exit("UIDVALIDITY changed since the plan: nothing trashed")
    for i in range(0, len(rows), 1000):
        chunk = rows[i:i + 1000]
        typ, d = m.uid("STORE", ranges([r[0] for r in chunk]), "+X-GM-LABELS", "(\\Trash)")
        if typ != "OK":
            sys.exit(f"STORE failed: {d}")
        db.executemany("update msgs set state='trashed' where gm_msgid=?", [(r[1],) for r in chunk])
        db.commit()
        print(f"  trashed {i + len(chunk)}/{len(rows)}", flush=True)
    m.logout()
    status(account)


def status(account):
    db, d = db_open(account)
    for state, source, n, size in db.execute(
            "select state, coalesce(source,''), count(*), sum(size) from msgs group by 1,2 order by 1,2"):
        print(f"  {state:<9} {source:<6} {n:>8} messages  {size / 1e9:6.2f} GB")
    print("  unverified archived:", db.execute("select count(*) from msgs where state='archived' and verified=0").fetchone()[0])


if __name__ == "__main__":
    account, cutoff, cmd = sys.argv[1], sys.argv[2], sys.argv[3]
    {"plan": lambda: plan(account, cutoff), "local": lambda: local(account), "fetch": lambda: fetch(account),
     "verify": lambda: sys.exit(1 if verify(account) else 0), "trash": lambda: trash(account),
     "status": lambda: status(account)}[cmd]()
