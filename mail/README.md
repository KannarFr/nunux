# mail archive

Mail older than 30 days is moved off the mail servers every day, so Thunderbird stays light. The
messages end up **on the NAS only**; this machine keeps a small index, so searching works offline.

    bin/mail-archive                 the daily pass (what the timer runs); `mail-archive status`
    bin/mail-search                  search, read and export archived mail
    mail/                            the Python behind both

## Where things are

| What | Where |
|---|---|
| The mail (mbox segments) | NAS: `<nas>/<account>/<year>.mbox` (first import) and `<nas>/<account>/<year>/<run>.mbox` (daily runs) |
| Index per account (`index.sqlite`) | here, `~/.local/share/mail-archive/<account>/`; a copy goes to the NAS next to the segments |
| Search index (`search.sqlite`), run log (`runs.jsonl`) | here, `~/.local/share/mail-archive/`; `runs.jsonl` is copied to the NAS |
| Settings and passwords | `~/.local/share/mail-archive.env` (chmod 600, never tracked) |

The accounts are the `gmail.` and `imap.` lines of the settings file (see below).

Each archived message starts with added headers: `X-GM-MSGID` + `X-Gmail-Labels` (Gmail, like a
Google Takeout export) or `X-Archive-Folder` + `X-Archive-UID` (the others). Records are mboxrd
with LF line endings, so any mbox tool reads a segment.

## Searching

    bin/mail-search find facture orange --since 2025-01-01      # sender, recipients, subject, folder
    bin/mail-search find 'sender:bank subject:"relevé de compte"' -a gmail
    bin/mail-search text relance impayé -a example             # words in the subject or the body
    bin/mail-search show 345600                                  # read one; the id is the first column
    bin/mail-search show 345600 --raw > mail.eml                 # the original, to open or re-import
    bin/mail-search grep 'FR76[0-9 ]{20,}'                      # regex over the raw messages

- `find` and `text` only use the local index: instant, and they work away from the NAS. `find` takes
  SQLite FTS5 syntax (words are ANDed; `"phrase"`, `prefix*`, `OR`, `NOT`, `column:word`); `text`
  takes words, `prefix*`, `OR`, `NOT` but no phrases. Bodies are indexed as text (HTML stripped,
  base64 and quoted-printable decoded, first 200 000 characters); attachments are not.
- `show` fetches that one message from the NAS (a ranged read over ssh).
- `grep` runs on the NAS over every segment (awk, POSIX extended regex, case-insensitive): about
  4 MB/s on a small ARM NAS, so an hour for the whole archive — narrow it with `-a` — and
  it sees the bytes as sent, so encoded text does not match. Use it for patterns `text` cannot express.
- `-a` filters on part of the account address, `--since`/`--until` on the date, `-n` on the row count.

To put a message back in Thunderbird, open the `.eml` from `show --raw`.

## The daily pass

`bin/mail-archive` does, per account, with the cutoff at today minus 30 days:

1. **plan**: list what is older than the cutoff. Drafts, Trash, Junk and Templates are left alone.
2. **local**: copy the messages Thunderbird already holds on disk, when the copy is byte-exact.
3. **fetch**: download the rest over IMAP.
4. **verify**: re-read every new record from disk.
5. **spotcheck**: download 25 random new records again and compare them byte for byte.
6. **trash**: only then, move them to the account's Trash.

An account stops at its first failing step, so nothing reaches Trash unverified; the next run
resumes. After the accounts: the search index takes in the new segments, then each segment is
**shipped** — uploaded to `<name>.part`, checksummed on the NAS with `sha256sum`, renamed, recorded
in the `shipped` table, and only then deleted here. With the NAS unreachable (or `nas=` not set)
the segments stay in `~/.local/share/mail-archive` and go with the next run; `mail-archive status`
shows `(not shipped)` or `(ship FAILED)`.

    bin/mail-archive status          # the last 15 runs, one line each
    journalctl --user -u mail-archive.service -e
    systemctl --user list-timers mail-archive.timer

Gmail empties its Trash by itself after 30 days. **Orange and OVH do not**: their Trash keeps
growing on the server until it is emptied by hand.

## Settings: `~/.local/share/mail-archive.env`

`key=value` lines, chmod 600:

    nas=user@nas.example.org:/share/homes/user/mail-archive      # ssh target:absolute path
    nas_port=22                                                   # optional
    gmail.someone@gmail.com=ImapMail/imap.gmail.com               # a Gmail account, and where
                                                                  # Thunderbird caches it (under the profile)
    imap.someone@example.org=imap.example.org|ImapMail/imap.example.org|INBOX/Trash
                                                                  # host | Thunderbird cache | Trash folder
    someone@example.org=…                                         # its password

- `nas=` is an ssh target (key authentication, no prompt: the timer runs unattended) or a plain
  directory (`nas=/mnt/nas/mail-archive`) when the share is mounted. The NAS only needs `sh`, `cat`,
  `mkdir`, `mv`, `rm`, `tail`, `head`, `awk` and `sha256sum` (BusyBox is enough: QTS has no Python).
- The ssh key lives in gpg-agent, so the service is given its socket (`SSH_AUTH_SOCK` in the unit).
  If the agent has no usable key at run time, shipping fails and is retried by the next run.
- Gmail needs no secret: the tools use the Google OAuth token Thunderbird has saved, so the account
  must stay configured in Thunderbird (profile `~/.thunderbird/*.default-release`, no primary password).
- A password account with no line is skipped and reported as such in the run.

## What is and is not backed up

The mail exists once, on the NAS: its safety is the NAS's (RAID, QTS snapshots). The local indexes can
be rebuilt from the NAS copies of `index.sqlite` (then `mail-search index`, which re-reads every
message over ssh — slow). There is no second copy of the segments unless the NAS itself is backed up.

To add an account, add its `gmail.` or `imap.` line (and a password line for `imap.`); the next run
takes it in.
