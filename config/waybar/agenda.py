#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = ["icalendar>=6", "recurring-ical-events>=3"]
# ///
"""Waybar custom/agenda tile: the next meeting, from Google secret iCal feeds.

Feeds: one URL per line in ~/.config/agenda/urls (mode 600, never in this
repo: a secret address gives read access to the whole calendar). Without that
file the tile stays empty, so a machine without it (ocean) shows nothing.

What it shows (one JSON line {text, tooltip, class, alt} per tick):
  - a meeting that starts within the hour:  "14:30 Daily · dans 25 min"
    (class "soon" under 10 min, else "upcoming")
  - otherwise a meeting in progress:        "Daily · en cours → 15:00" ("now")
  - from 18:00, once nothing is left today, the first meeting of the next
    day that has one, up to 3 days ahead:  "demain 09:30 Point" ("tomorrow")
  - nothing otherwise (empty text: waybar hides the tile).
All-day events, cancelled ones and those the calendar owner declined are
skipped; the same event in both calendars is shown once.

Feeds are fetched at most every 5 min; the expanded occurrences are cached in
~/.cache/agenda/events.json, so a tick only reads that file. A failed fetch
keeps the previous copy of that feed.

`agenda.py open` (the tile's on-click) opens the meeting link of the event
shown (Meet, Zoom, Teams), else Google Calendar.
"""

import datetime as dt
import html
import json
import os
import re
import subprocess
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

URLS = Path.home() / ".config/agenda/urls"
CACHE = Path.home() / ".cache/agenda"
EVENTS = CACHE / "events.json"
SHOWN = CACHE / "shown.json"
REFRESH = 300          # seconds between fetches
LEAD = dt.timedelta(hours=1)
SOON = dt.timedelta(minutes=10)
EVENING = dt.time(18, 0)
LOOKAHEAD_DAYS = 3
TITLE_MAX = 32
CALENDAR_URL = "https://calendar.google.com/calendar/r"
LINK_RE = re.compile(
    r"https://(?:meet\.google\.com/[a-z0-9-]+|[\w.-]*zoom\.us/j/[^\s<>\"]+"
    r"|teams\.microsoft\.com/l/meetup-join/[^\s<>\"]+)"
)
WEEKDAYS = ["lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi", "dimanche"]


def now() -> dt.datetime:
    # AGENDA_NOW="2026-11-25T17:40" pins the clock, for testing.
    fake = os.environ.get("AGENDA_NOW")
    t = dt.datetime.fromisoformat(fake) if fake else dt.datetime.now()
    return t.astimezone()


def feed_path(i: int) -> Path:
    return CACHE / f"feed{i}.ics"


def fetch(urls: list[str]) -> None:
    for i, url in enumerate(urls):
        try:
            with urllib.request.urlopen(url, timeout=10) as r:
                data = r.read()
            if b"BEGIN:VCALENDAR" in data:
                tmp = feed_path(i).with_suffix(".tmp")
                tmp.write_bytes(data)
                tmp.replace(feed_path(i))
        except OSError:
            pass  # keep the previous copy


def owner(url: str) -> str:
    m = re.search(r"/ical/([^/]+)/", url)
    return urllib.parse.unquote(m.group(1)).lower() if m else ""


def declined(ev, me: str) -> bool:
    attendees = ev.get("ATTENDEE")
    if attendees is None:
        return False
    if not isinstance(attendees, list):
        attendees = [attendees]
    for a in attendees:
        if str(a).lower().removeprefix("mailto:") == me:
            return str(a.params.get("PARTSTAT", "")).upper() == "DECLINED"
    return False


def link(ev) -> str | None:
    for key in ("X-GOOGLE-CONFERENCE", "LOCATION", "DESCRIPTION"):
        m = LINK_RE.search(str(ev.get(key, "")))
        if m:
            return m.group(0)
    return None


def expand(urls: list[str], t: dt.datetime) -> list[dict]:
    import icalendar
    import recurring_ical_events

    start = t - dt.timedelta(hours=12)
    end = t + dt.timedelta(days=LOOKAHEAD_DAYS + 1)
    seen: dict[tuple, dict] = {}
    for i, url in enumerate(urls):
        p = feed_path(i)
        if not p.exists():
            continue
        cal = icalendar.Calendar.from_ical(p.read_bytes())
        name = str(cal.get("X-WR-CALNAME", "")) or owner(url)
        me = owner(url)
        for ev in recurring_ical_events.of(cal).between(start, end):
            s = ev.get("DTSTART").dt
            if not isinstance(s, dt.datetime):
                continue  # all-day
            if str(ev.get("STATUS", "")).upper() == "CANCELLED" or declined(ev, me):
                continue
            e = ev.get("DTEND").dt if ev.get("DTEND") else s + ev.duration
            s, e = s.astimezone(), e.astimezone()
            key = (str(ev.get("UID")), s.isoformat())
            if key in seen:
                seen[key]["cal"] += f", {name}"
                continue
            seen[key] = {
                "title": str(ev.get("SUMMARY", "(sans titre)")).strip(),
                "start": s.isoformat(),
                "end": e.isoformat(),
                "cal": name,
                "link": link(ev),
            }
    return sorted(seen.values(), key=lambda x: x["start"])


def load_events(t: dt.datetime) -> list[dict]:
    if not URLS.exists():
        return []
    urls = [u.strip() for u in URLS.read_text().splitlines() if u.strip()]
    CACHE.mkdir(parents=True, exist_ok=True)
    fresh = EVENTS.exists() and time.time() - EVENTS.stat().st_mtime < REFRESH
    if fresh:
        cached = json.loads(EVENTS.read_text())
        # Re-expand when the cached window no longer covers [now, lookahead].
        if (dt.datetime.fromisoformat(cached["since"]) <= t
                < t + dt.timedelta(days=LOOKAHEAD_DAYS) < dt.datetime.fromisoformat(cached["until"])):
            return cached["events"]
    if not fresh:
        fetch(urls)
    events = expand(urls, t)
    since = t - dt.timedelta(hours=12)
    until = t + dt.timedelta(days=LOOKAHEAD_DAYS + 1)
    tmp = EVENTS.with_suffix(".tmp")
    tmp.write_text(json.dumps({"since": since.isoformat(), "until": until.isoformat(), "events": events}))
    tmp.replace(EVENTS)
    return events


def short(title: str) -> str:
    return title if len(title) <= TITLE_MAX else title[: TITLE_MAX - 1] + "…"


def esc(s: str) -> str:
    return html.escape(s, quote=False)


def hm(d: dt.datetime) -> str:
    return d.strftime("%H:%M")


def day_label(d: dt.date, today: dt.date) -> str:
    return "demain" if d == today + dt.timedelta(days=1) else WEEKDAYS[d.weekday()]


def pick(events: list[dict], t: dt.datetime) -> tuple[dict | None, str, str]:
    ev = [dict(x, s=dt.datetime.fromisoformat(x["start"]), e=dt.datetime.fromisoformat(x["end"]))
          for x in events]
    upcoming = [x for x in ev if t < x["s"] <= t + LEAD]
    if upcoming:
        x = upcoming[0]
        mins = int((x["s"] - t).total_seconds() // 60)
        when = "maintenant" if mins < 1 else f"dans {mins} min"
        cls = "soon" if x["s"] - t <= SOON else "upcoming"
        return x, f"{hm(x['s'])} {esc(short(x['title']))} · {when}", cls
    current = [x for x in ev if x["s"] <= t < x["e"]]
    if current:
        x = current[-1]
        return x, f"{esc(short(x['title']))} · en cours → {hm(x['e'])}", "now"
    today = t.date()
    left_today = [x for x in ev if x["s"] > t and x["s"].date() == today]
    if t.time() >= EVENING and not left_today:
        later = [x for x in ev if x["s"].date() > today]
        if later:
            x = later[0]
            return x, f"{day_label(x['s'].date(), today)} {hm(x['s'])} {esc(short(x['title']))}", "tomorrow"
    return None, "", ""


def tooltip(events: list[dict], t: dt.datetime) -> str:
    today = t.date()
    lines, nextday = [], None
    for x in events:
        s, e = dt.datetime.fromisoformat(x["start"]), dt.datetime.fromisoformat(x["end"])
        if e <= t:
            continue
        if s.date() == today:
            lines.append(f"{hm(s)}–{hm(e)}  {esc(x['title'])}  <small>({esc(x['cal'])})</small>")
        elif s.date() > today and nextday is None:
            nextday = f"{day_label(s.date(), today).capitalize()} {hm(s)}  {esc(x['title'])}  <small>({esc(x['cal'])})</small>"
    out = ["<b>Aujourd'hui</b>"] + (lines or ["rien d'autre"])
    if nextday:
        out += ["", nextday]
    return "\n".join(out)


def main() -> None:
    t = now()
    try:
        events = load_events(t)
    except Exception as exc:  # never break the bar
        print(json.dumps({"text": "", "tooltip": f"agenda: {exc}", "class": "error"}))
        return
    shown, text, cls = pick(events, t)
    if len(sys.argv) > 1 and sys.argv[1] == "open":
        target = (shown or {}).get("link") or CALENDAR_URL
        subprocess.Popen(["xdg-open", target], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return
    if text:
        text = f"\uf073  {text}"
    print(json.dumps({"text": text, "tooltip": tooltip(events, t) if text else "", "class": cls, "alt": cls}))


if __name__ == "__main__":
    main()
