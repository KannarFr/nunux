"""Open an IMAP session on the Clever Cloud Gmail account using Thunderbird's
saved Google OAuth refresh token (no password, no browser), through the mail
archive's thunderbird_oauth module in this repo."""
import os, sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.realpath(__file__)), "../../../mail"))
import thunderbird_oauth

ACCOUNT = "alexandre.duval@clever.cloud"
FOLDER = "INBOX/GitLab"


def connect(readonly=True):
    m = thunderbird_oauth.connect(ACCOUNT)
    typ, _ = m.select(f'"{FOLDER}"', readonly=readonly)
    if typ != "OK":
        raise SystemExit("cannot select " + FOLDER)
    return m
