#!/usr/bin/env python3
"""List unread INBOX/GitLab mails grouped by thread -> threads.json (+ summary on stdout).
Read-only: BODY.PEEK never sets \\Seen."""
import email, email.header, json, re, sys
from gmail_imap import connect

out = sys.argv[1] if len(sys.argv) > 1 else "threads.json"
m = connect(readonly=True)
_, data = m.uid("SEARCH", None, "UNSEEN")
uids = data[0].split()


def hdr(msg, k):
    v = msg.get(k)
    return str(email.header.make_header(email.header.decode_header(v))) if v else ""


def text(msg):
    for part in msg.walk():
        if part.get_content_type() == "text/plain":
            return part.get_payload(decode=True).decode(part.get_content_charset() or "utf-8", "replace")
    return ""


threads = {}
for i in range(0, len(uids), 50):
    chunk = b",".join(uids[i:i + 50])
    _, resp = m.uid("FETCH", chunk, "(UID BODY.PEEK[])")
    for item in resp:
        if not isinstance(item, tuple):
            continue
        uid = re.search(rb"UID (\d+)", item[0]).group(1).decode()
        msg = email.message_from_bytes(item[1])
        subj = re.sub(r"\s+", " ", hdr(msg, "Subject")).strip()
        key = re.sub(r"^(re|fwd?):\s*", "", subj, flags=re.I)
        body = text(msg)
        # the "Reviewers: kannar, ..." footer is not a mention; only @kannar counts
        mention = "@kannar" in body
        t = threads.setdefault(key, {"subject": key, "project": hdr(msg, "X-GitLab-Project-Path"),
                                     "uids": [], "reasons": set(), "mention": False, "merged": False,
                                     "snippets": []})
        t["uids"].append(uid)
        t["reasons"].add(hdr(msg, "X-GitLab-NotificationReason") or "-")
        t["mention"] |= mention
        t["merged"] |= bool(re.search(r"\bwas merged\b|Merge request .* was merged|merged\b.*!\d+", body[:600]))
        if len(t["snippets"]) < 2:
            t["snippets"].append(re.sub(r"\s+", " ", body)[:300])

for t in threads.values():
    t["reasons"] = sorted(t["reasons"])
json.dump(list(threads.values()), open(out, "w"), indent=1)
print(f"{len(uids)} unread in {len(threads)} threads -> {out}")
for n, t in enumerate(threads.values()):
    flags = ("M" if t["mention"] else "-") + ("m" if t["merged"] else "-")
    print(f"{n:3} {flags} {len(t['uids']):2} {t['project']:40} {t['subject'][:110]}")
m.logout()
