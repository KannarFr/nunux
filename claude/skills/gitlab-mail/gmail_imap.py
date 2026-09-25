"""Open an IMAP session on the Clever Cloud Gmail account using Thunderbird's
saved Google OAuth refresh token (no password, no browser)."""
import base64, ctypes, glob, imaplib, json, os, urllib.parse, urllib.request

ACCOUNT = "alexandre.duval@clever-cloud.com"
FOLDER = "INBOX/GitLab"
# Thunderbird's public Google OAuth client (OAuth2Providers.sys.mjs)
CLIENT_ID = "406964657835-aq8lmia8j95dhl1a2bvharmfk3t1hgqj.apps.googleusercontent.com"
CLIENT_SECRET = "kSmqreRr0qwBWJgbf5Y-PjSU"


def profile():
    return glob.glob(os.path.expanduser("~/.thunderbird/*.default-release"))[0]


class SECItem(ctypes.Structure):
    _fields_ = [("type", ctypes.c_uint), ("data", ctypes.c_char_p), ("len", ctypes.c_uint)]


def refresh_token():
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

    for l in json.load(open(os.path.join(prof, "logins.json")))["logins"]:
        if l["hostname"] == "oauth://accounts.google.com" and "mail.google.com" in (l.get("httpRealm") or ""):
            if dec(l["encryptedUsername"]) == ACCOUNT:
                return dec(l["encryptedPassword"])
    raise SystemExit("no refresh token for " + ACCOUNT)


def access_token():
    body = urllib.parse.urlencode({
        "client_id": CLIENT_ID, "client_secret": CLIENT_SECRET,
        "refresh_token": refresh_token(), "grant_type": "refresh_token",
    }).encode()
    with urllib.request.urlopen("https://oauth2.googleapis.com/token", body) as r:
        return json.load(r)["access_token"]


def connect(readonly=True):
    tok = access_token()
    m = imaplib.IMAP4_SSL("imap.gmail.com")
    m.authenticate("XOAUTH2", lambda _: f"user={ACCOUNT}\x01auth=Bearer {tok}\x01\x01".encode())
    typ, _ = m.select(f'"{FOLDER}"', readonly=readonly)
    if typ != "OK":
        raise SystemExit("cannot select " + FOLDER)
    return m
