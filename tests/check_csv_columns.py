#!/usr/bin/env python3
"""Static check: every CSV data row must have exactly as many fields as its header.

A research CSV whose header and rows drift apart silently corrupts every
downstream statistic, and MQL5 will not warn about it. This parses the EA
source and compares the number of Row* calls in each header/row pair.
"""
import re
import sys
from pathlib import Path

EA = Path(__file__).resolve().parent.parent / "MQL5" / "Experts" / "daxDzida" / "DaxDzida_Phase1.mq5"

BLOCK_RE = re.compile(r"RowReset\(\);(.*?)FileWrite\((g_csv|g_tzCsv), g_row\);", re.S)
CALL_RE = re.compile(r"\bRowAdd[ID]?\s*\(")


def blocks(src):
    """Return (handle, field_count) for every Row-building block, in file order."""
    return [(m.group(2), len(CALL_RE.findall(m.group(1)))) for m in BLOCK_RE.finditer(src)]


def main():
    src = EA.read_text(encoding="utf-8", errors="replace")
    counts = blocks(src)

    if len(counts) != 4:
        print(f"FAIL: expected 4 Row-building blocks "
              f"(sessions header/row, tz header/row), found {len(counts)}")
        return 1

    sess = [n for h, n in counts if h == "g_csv"]
    tz = [n for h, n in counts if h == "g_tzCsv"]
    if len(sess) != 2 or len(tz) != 2:
        print(f"FAIL: expected one header and one row per CSV, got {counts}")
        return 1
    sess_hdr, sess_row = sess
    tz_hdr, tz_row = tz
    ok = True

    if sess_hdr != sess_row:
        print(f"FAIL: session CSV header has {sess_hdr} columns "
              f"but the data row writes {sess_row}")
        ok = False
    else:
        print(f"  session CSV: {sess_hdr} columns, header and row agree")

    if tz_hdr != tz_row:
        print(f"FAIL: timezone CSV header has {tz_hdr} columns "
              f"but the data row writes {tz_row}")
        ok = False
    else:
        print(f"  timezone CSV: {tz_hdr} columns, header and row agree")

    # Every field the Phase 1 brief asks for must be present by name.
    required = [
        "date", "zoneStartWarsaw", "zoneEndWarsaw", "zoneHigh", "zoneLow", "zoneRange",
        "tpLong", "tpShort", "firstBreakTime", "firstBreakDirection", "firstBreakBid",
        "entryPrice", "spreadAtEntry", "oppositeBreakTime", "reversalCount", "exitTime",
        "exitPrice", "exitReason", "maePoints", "mfePoints", "holdingSeconds",
        "grossPnLPoints", "netPnLPoints", "netPnLMoney", "dayOfWeek", "serverTimeArm",
        "warsawTimeArm", "utcOffsetServerSec", "utcOffsetWarsawSec", "configurationId",
    ]
    header_names = set(re.findall(r'RowAdd\("([A-Za-z0-9_]+)"\);', src))
    missing = [f for f in required if f not in header_names]
    if missing:
        print("FAIL: research CSV is missing required fields: " + ", ".join(missing))
        ok = False
    else:
        print(f"  all {len(required)} brief-mandated fields present")

    # The special session states must all be emitted somewhere.
    for state in ["NO_BREAKOUT", "NO_TICKS", "ENTRY_OVERSHOOT_BEYOND_TP", "DOUBLE_BREAKOUT"]:
        if f'"{state}"' not in src:
            print(f"FAIL: session state '{state}' is never written to the CSV")
            ok = False

    print("RESULT: PASS" if ok else "RESULT: FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
