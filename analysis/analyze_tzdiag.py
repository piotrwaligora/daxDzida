#!/usr/bin/env python3
"""Analyse a daxDzida TZDIAG run: is the clock right, and is the data usable?

The whole study rests on the 08:55-09:00 Europe/Warsaw window being the window
the EA actually measured, so the evidence for that claim lives in the repository
rather than in a chat log.

    python3 analysis/analyze_tzdiag.py <path to daxDzida_TZDIAG_<SYM>_days.csv>

Exit code 0 = the clock is verified and the data is usable for Phase 1.
"""
import csv
import datetime as dt
import sys
from collections import Counter

ZONE_START_MS = 8 * 3600000 + 55 * 60000
CUTOFF_30_MS = 9 * 3600000 + 30 * 60000
CUTOFF_60_MS = 10 * 3600000


def tod_ms(stamp: str) -> int:
    """'YYYY-MM-DD HH:MM:SS.mmm' -> milliseconds since Warsaw midnight."""
    clock = stamp.split(" ")[1]
    h, m, rest = clock.split(":")
    s, ms = rest.split(".")
    return int(h) * 3600000 + int(m) * 60000 + int(s) * 1000 + int(ms)


def fmt(ms: int) -> str:
    return f"{ms // 3600000:02d}:{ms // 60000 % 60:02d}:{ms // 1000 % 60:02d}"


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    rows = list(csv.DictReader(open(sys.argv[1], encoding="utf-8-sig"), delimiter=";"))
    if not rows:
        print("FAIL: empty diagnostic file")
        return 1

    problems = []
    print(f"days with tick data : {len(rows)}   "
          f"{rows[0]['serverDate']} -> {rows[-1]['serverDate']}")

    # ---------------------------------------------------------- timezone ---
    print("\n--- TIMEZONE ---")
    flags = Counter(r["tzFlag"] for r in rows)
    invariant = Counter(r["serverMinusWarsawSec"] for r in rows)
    print(f"tzFlag values         : {dict(flags)}   (0 = unambiguous)")
    print(f"server minus Warsaw   : {dict(invariant)} seconds")

    if set(flags) != {"0"}:
        problems.append("some days had an ambiguous or non-existent server timestamp")

    # An EU-DST server (EET/EEST) must sit a constant offset from Warsaw all
    # year, because both clocks switch at the same UTC instant. A value that
    # changes across the DST boundary means the server timezone model is wrong.
    if len(invariant) != 1:
        problems.append(
            f"server-to-Warsaw offset is NOT constant ({dict(invariant)}); "
            "the configured server timezone model is wrong")
    else:
        print("OK  the server clock holds a constant offset from Warsaw all year")

    pairs = sorted({(int(r["utcOffsetServerSec"]), int(r["utcOffsetWarsawSec"])) for r in rows})
    print(f"(server,Warsaw) UTC offsets observed: {pairs}")

    prev = None
    for r in rows:
        key = (r["utcOffsetServerSec"], r["utcOffsetWarsawSec"])
        if prev and key != prev[1]:
            print(f"DST transition: {prev[0]} -> {r['serverDate']}   "
                  f"server {prev[1][0]}->{key[0]}, Warsaw {prev[1][1]}->{key[1]}")
        prev = (r["serverDate"], key)

    # ------------------------------------------------------ window cover ---
    print("\n--- SESSION WINDOW COVERAGE (Warsaw) ---")
    first = [tod_ms(r["firstTickWarsaw"]) for r in rows]
    last = [tod_ms(r["lastTickWarsaw"]) for r in rows]
    print(f"first tick, earliest / latest : {fmt(min(first))} / {fmt(max(first))}")
    print(f"last  tick, earliest / latest : {fmt(min(last))} / {fmt(max(last))}")

    late = [r for r in rows if tod_ms(r["firstTickWarsaw"]) > ZONE_START_MS]
    short30 = [r for r in rows if tod_ms(r["lastTickWarsaw"]) < CUTOFF_30_MS]
    short60 = [r for r in rows if tod_ms(r["lastTickWarsaw"]) < CUTOFF_60_MS]
    print(f"days starting after 08:55  : {len(late)}")
    print(f"days ending before 09:30   : {len(short30)}")
    print(f"days ending before 10:00   : {len(short60)}")
    for label, bad in (("start after 08:55", late), ("end before 10:00", short60)):
        if bad:
            problems.append(f"{len(bad)} day(s) {label}: "
                            + ", ".join(r["serverDate"] for r in bad[:5]))

    # NOTE: this file reports the first and last tick of each day, not tick
    # counts inside 08:55-09:00. A gap over that window would only show up as
    # NO_TICKS / zoneTicks in a research run's session CSV.

    # -------------------------------------------------------- calendar ----
    print("\n--- CALENDAR COVERAGE ---")
    have = {dt.date.fromisoformat(r["serverDate"]) for r in rows}
    d, end = min(have), max(have)
    weekdays = []
    while d <= end:
        if d.weekday() < 5:
            weekdays.append(d)
        d += dt.timedelta(days=1)
    missing = [x for x in weekdays if x not in have]
    weekend = sorted(x for x in have if x.weekday() >= 5)

    print(f"weekdays in range          : {len(weekdays)}")
    print(f"weekdays with tick data    : {len(weekdays) - len(missing)}")
    print(f"weekdays without tick data : {len(missing)}")
    for x in missing:
        print(f"    {x}  {x.strftime('%a')}")
    if weekend:
        print(f"weekend days with ticks    : {len(weekend)} "
              f"(filter these out by dayOfWeek in analysis)")

    # ---------------------------------------------------------- volume ----
    print("\n--- TICK VOLUME ---")
    counts = sorted((int(r["tickCount"]), r["serverDate"], r["serverDow"]) for r in rows)
    total = sum(c[0] for c in counts)
    print(f"total {total:,}   mean {total // len(counts):,}   "
          f"median {counts[len(counts) // 2][0]:,}   min {counts[0][0]:,}")
    print("five thinnest days:")
    for n, day, dow in counts[:5]:
        print(f"    {day} {dow}  {n:>8,}")

    # -------------------------------------------------------- verdict -----
    print("\n" + "=" * 60)
    if problems:
        print("RESULT: FAIL - do not run research backtests on this configuration")
        for p in problems:
            print("  * " + p)
        return 1
    print("RESULT: PASS - clock verified, data usable")
    print(f"  expected valid Phase 1 sessions: {len(rows)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
