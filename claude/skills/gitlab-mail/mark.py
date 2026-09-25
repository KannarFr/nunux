#!/usr/bin/env python3
"""Mark threads read by index (as printed by fetch.py): mark.py threads.json 0 3 7-12"""
import json, sys
from gmail_imap import connect

threads = json.load(open(sys.argv[1]))
idx = set()
for a in sys.argv[2:]:
    lo, _, hi = a.partition("-")
    idx.update(range(int(lo), int(hi or lo) + 1))
uids = [u for i in sorted(idx) for u in threads[i]["uids"]]
if not uids:
    sys.exit("nothing to mark")
m = connect(readonly=False)
for i in range(0, len(uids), 200):
    typ, _ = m.uid("STORE", ",".join(uids[i:i + 200]), "+FLAGS", r"(\Seen)")
    if typ != "OK":
        sys.exit("STORE failed")
print(f"marked {len(uids)} mails read across {len(idx)} threads")
m.logout()
