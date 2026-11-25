#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = ["icalendar>=6", "recurring-ical-events>=3"]
# ///
"""Waybar custom/agenda tile: the next meeting, from Google secret iCal feeds.

Feeds: one URL per line in ~/.config/agenda/urls (mode 600, never in this
repo: a secret address gives read access to the whole calendar). Without that
file the tile shows only its icon and an empty grid.

What it shows (one JSON line {text, tooltip, class, alt} per tick):
  - a meeting that starts within the hour:  "14:30 Daily · dans 25 min"
    (class "soon" under 10 min, else "upcoming")
  - otherwise a meeting in progress:        "Daily · en cours → 15:00" ("now")
  - from 18:00, once nothing is left today, the first meeting of the next
    day that has one, up to 3 days ahead:  "demain 09:30 Point" ("tomorrow")
  - the bare calendar icon otherwise ("idle"), so it can always be hovered.
The tooltip shows today and the next two days as three columns on a
half-hour grid, one color per calendar, past events dimmed, the current
one in bold, the current half hour marked in red in the gutter.
Cancelled events and those the calendar owner declined are skipped;
all-day events only appear in the tooltip; the same event in both
calendars is shown once.

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


def window(t: dt.datetime) -> tuple[dt.datetime, dt.datetime]:
    # From midnight today (the tooltip lists the whole day) to the end of the
    # lookahead.
    start = dt.datetime.combine(t.date(), dt.time()).astimezone()
    return start, start + dt.timedelta(days=LOOKAHEAD_DAYS + 1)


def expand(urls: list[str], t: dt.datetime) -> list[dict]:
    import icalendar
    import recurring_ical_events

    start, end = window(t)
    seen: dict[tuple, dict] = {}
    for i, url in enumerate(urls):
        p = feed_path(i)
        if not p.exists():
            continue
        cal = icalendar.Calendar.from_ical(p.read_bytes())
        name = str(cal.get("X-WR-CALNAME", "")) or owner(url)
        me = owner(url)
        for ev in recurring_ical_events.of(cal).between(start, end):
            if str(ev.get("STATUS", "")).upper() == "CANCELLED" or declined(ev, me):
                continue
            s = ev.get("DTSTART").dt
            e = ev.get("DTEND").dt if ev.get("DTEND") else s + ev.duration
            allday = not isinstance(s, dt.datetime)
            if allday:  # dates; DTEND is exclusive
                s = dt.datetime.combine(s, dt.time()).astimezone()
                e = dt.datetime.combine(e, dt.time()).astimezone()
            else:
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
                "allday": allday,
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
        # Re-expand when the cached window is not the one for today.
        if cached.get("since") == window(t)[0].isoformat():
            return cached["events"]
    if not fresh:
        fetch(urls)
    events = expand(urls, t)
    since, until = window(t)
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
          for x in events if not x.get("allday")]
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


MONTHS = ["janvier", "février", "mars", "avril", "mai", "juin", "juillet",
          "août", "septembre", "octobre", "novembre", "décembre"]
MONTHS_SHORT = ["janv.", "févr.", "mars", "avr.", "mai", "juin", "juil.",
                "août", "sept.", "oct.", "nov.", "déc."]
TOOLTIP_DAYS = 3  # today, tomorrow, the day after


SLOT = dt.timedelta(minutes=30)
DAY_FROM, DAY_TO = 8, 19   # hours always shown; widened to fit the events
COL = 30                   # characters per day column
COLORS = ["#2980b9", "#3a8a3a", "#8e44ad", "#b8a020"]  # one per calendar


def cell(text: str, bg: str | None = None, dim: bool = False, bold: bool = False) -> str:
    text = text[:COL - 1] + "…" if len(text) > COL else text.ljust(COL)
    out = esc(text)
    attrs = []
    if bg:
        attrs.append(f'background="{bg}" foreground="#ffffff"')
    if dim:
        attrs.append('alpha="45%"')
    if attrs:
        out = f"<span {' '.join(attrs)}>{out}</span>"
    return f"<b>{out}</b>" if bold else out


def tooltip(events: list[dict], t: dt.datetime) -> str:
    """Today and the next two days as three columns on a half-hour grid."""
    today = t.date()
    days = [today + dt.timedelta(days=n) for n in range(TOOLTIP_DAYS)]
    cals = sorted({x["cal"].split(", ")[0] for x in events})
    color = {c: COLORS[i % len(COLORS)] for i, c in enumerate(cals)}
    ev = [dict(x, s=dt.datetime.fromisoformat(x["start"]), e=dt.datetime.fromisoformat(x["end"]))
          for x in events]

    def of_day(d, allday):
        lo = dt.datetime.combine(d, dt.time()).astimezone()
        return lo, [x for x in ev if bool(x.get("allday")) == allday
                    and x["s"] < lo + dt.timedelta(days=1) and x["e"] > lo]

    # Hours shown: DAY_FROM-DAY_TO, widened to the earliest start / latest end.
    h0, h1 = DAY_FROM, DAY_TO
    for d in days:
        lo, xs = of_day(d, False)
        for x in xs:
            h0 = min(h0, max(0, int((x["s"] - lo).total_seconds() // 3600)))
            h1 = max(h1, min(24, -int(-(x["e"] - lo).total_seconds() // 3600)))

    gutter = 6
    names = []
    for n, d in enumerate(days):
        label = ["Aujourd'hui", "Demain"][n] if n < 2 else WEEKDAYS[d.weekday()].capitalize()
        names.append(cell(f"{label} {d.day} {MONTHS_SHORT[d.month - 1]}", bold=True))
    rows = [" " * gutter + " ".join(names)]

    alldays = [of_day(d, True)[1] for d in days]
    for k in range(max(map(len, alldays), default=0)):
        cells = []
        for xs in alldays:
            x = xs[k] if k < len(xs) else None
            cells.append(cell(f" {x['title']}", color[x["cal"].split(', ')[0]]) if x else cell(""))
        rows.append(" " * gutter + " ".join(cells))

    slots = int((h1 - h0) * 3600 // SLOT.total_seconds())
    for k in range(slots):
        cells = []
        for d in days:
            lo, xs = of_day(d, False)
            a = lo + dt.timedelta(hours=h0) + k * SLOT
            b = a + SLOT
            on = [x for x in xs if x["s"] < b and x["e"] > a]
            starting = [x for x in on if x["s"] >= a or (k == 0 and x["s"] < a)]
            if not on:
                cells.append(cell(""))
                continue
            first = (starting or on)[0]
            bg = color[first["cal"].split(", ")[0]]
            past, current = first["e"] <= t, first["s"] <= t < first["e"]
            if starting:
                text = f"{hm(starting[0]['s'])} {starting[0]['title']}"
                if len(starting) > 1:  # keep the "+N" visible past the cut
                    more = f" +{len(starting) - 1}"
                    text = (text if len(text) + len(more) < COL - 1 else text[:COL - 3 - len(more)] + "…") + more
                if len(on) > len(starting):
                    text = "│" + text
                cells.append(cell(f" {text}", bg, dim=past, bold=current))
            else:
                cells.append(cell(" │", bg, dim=past))
        a = dt.datetime.combine(today, dt.time()).astimezone() + dt.timedelta(hours=h0) + k * SLOT
        mark = a <= t < a + SLOT
        hour = a.strftime("%H:%M") if a.minute == 0 or mark else ""
        g = f"{hour:<5} "
        if mark:
            g = f'<span foreground="#eb4d4b"><b>{g}</b></span>'
        rows.append(g + " ".join(cells))
    legend = "   ".join(f'<span foreground="{color[c]}">■</span> {esc(c)}' for c in cals)
    return "<tt>" + "\n".join(rows) + "</tt>\n\n" + legend


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
    # Always visible (the bare icon when nothing is due), so the agenda can be
    # hovered at any time.
    text = f"\uf073  {text}" if text else "\uf073"
    cls = cls or "idle"
    print(json.dumps({"text": text, "tooltip": tooltip(events, t), "class": cls, "alt": cls}))


if __name__ == "__main__":
    main()
