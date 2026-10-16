"""Gmail IMAP sessions from Thunderbird's saved Google OAuth refresh token (no password, no browser).
Shared by the mail archive and the gitlab-mail skill."""
import base64, ctypes, glob, imaplib, json, os, urllib.error, urllib.parse, urllib.request

# Thunderbird's public Google OAuth client (OAuth2Providers.sys.mjs)
CLIENT_ID = "406964657835-aq8lmia8j95dhl1a2bvharmfk3t1hgqj.apps.googleusercontent.com"
CLIENT_SECRET = "kSmqreRr0qwBWJgbf5Y-PjSU"
# Logins naming the same Google account (the Clever Cloud address was renamed on
# 2026-10-16). Thunderbird keeps the refresh token under whichever one it last
# authenticated as, so either may be the one in logins.json.
SAME_ACCOUNT = (("alexandre.duval@clever.cloud", "alexandre.duval@clever-cloud.com"),)


def profile():
    return glob.glob(os.path.expanduser("~/.thunderbird/*.default-release"))[0]


class SECItem(ctypes.Structure):
    _fields_ = [("type", ctypes.c_uint), ("data", ctypes.c_char_p), ("len", ctypes.c_uint)]


def logins(account):
    """account first, then the other logins for the same Google account."""
    for group in SAME_ACCOUNT:
        if account in group:
            return (account, *(n for n in group if n != account))
    return (account,)


def refresh_tokens(account):
    """[(login, refresh token)] for each of logins(account) Thunderbird has a token for, in that order."""
    prof = profile()
    nss = ctypes.CDLL("libnss3.so")
    if nss.NSS_Init(("sql:" + prof).encode()) != 0:
        raise SystemExit("NSS_Init failed")

    def dec(b64):
        raw = base64.b64decode(b64)
        inp, out = SECItem(0, raw, len(raw)), SECItem(0, None, 0)
        if nss.PK11SDR_Decrypt(ctypes.byref(inp), ctypes.byref(out), None) != 0:
            raise SystemExit("PK11SDR_Decrypt failed (primary password set?)")
        return ctypes.string_at(out.data, out.len).decode()

    wanted, saved = logins(account), {}
    for l in json.load(open(os.path.join(prof, "logins.json")))["logins"]:
        if l["hostname"] == "oauth://accounts.google.com" and "mail.google.com" in (l.get("httpRealm") or ""):
            name = dec(l["encryptedUsername"])
            if name in wanted:
                saved.setdefault(name, l["encryptedPassword"])
    found = [(name, dec(saved[name])) for name in wanted if name in saved]
    if not found:
        raise SystemExit("no refresh token for " + " or ".join(wanted))
    return found


def access_token(account):
    """(login, access token) from the first saved login whose refresh token Google still accepts;
    authenticate as that login. A revoked token (HTTP 400/401) moves on to the next login; any other
    error propagates as an OSError so callers can retry it."""
    refused = []
    for login, refresh in refresh_tokens(account):
        body = urllib.parse.urlencode({
            "client_id": CLIENT_ID, "client_secret": CLIENT_SECRET,
            "refresh_token": refresh, "grant_type": "refresh_token",
        }).encode()
        try:
            with urllib.request.urlopen("https://oauth2.googleapis.com/token", body) as r:
                return login, json.load(r)["access_token"]
        except urllib.error.HTTPError as e:
            if e.code not in (400, 401):
                raise
            refused.append(f"{login}: {e.code} {e.read().decode(errors='replace').strip()}")
    raise SystemExit("Google refused every saved token (" + "; ".join(refused) + "); "
                     "open Thunderbird so it signs in to that account again")


def connect(account):
    """An authenticated IMAP4_SSL session on imap.gmail.com."""
    login, tok = access_token(account)
    m = imaplib.IMAP4_SSL("imap.gmail.com")
    m.authenticate("XOAUTH2", lambda _: f"user={login}\x01auth=Bearer {tok}\x01\x01".encode())
    return m
