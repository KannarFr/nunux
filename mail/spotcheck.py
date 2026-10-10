#!/usr/bin/env python3
"""spotcheck.py <account> [n]: re-download n random archived messages and compare them byte for byte."""
import re, sys
import gmail_archive as a
import store

account, n = sys.argv[1], int(sys.argv[2]) if len(sys.argv) > 2 else 40
db, d = a.db_open(account)
rows = db.execute("select uid,gm_msgid,file,offset,length,source from msgs where state='archived' "
                  "order by random() limit ?", (n,)).fetchall()
m = a.connect(account); a.all_mail(m)
ok = bad = 0
for uid, gm, name, off, length, source in rows:
    typ, data = m.uid("FETCH", str(uid), "(X-GM-MSGID BODY.PEEK[])")
    text, lits = next(a.groups(data))
    assert re.search(rb"X-GM-MSGID (\d+)", text).group(1).decode() == gm, "uid no longer maps to this message"
    want = re.sub(rb"(?m)^(>*From )", rb">\1", lits[-1].replace(b"\r\n", b"\n"))
    rec = store.read_record(account, name, off, length)
    body = rec.split(b"\n", 3)[3]
    same = body in (want + b"\n", want + b"\n\n") or body.rstrip(b"\n") == want.rstrip(b"\n")
    ok += same; bad += not same
    if not same: print("DIFF", gm, source, len(body), len(want))
print(f"{ok} identical, {bad} different")
