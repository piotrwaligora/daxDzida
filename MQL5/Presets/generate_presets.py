#!/usr/bin/env python3
"""Single source of truth for the pre-registered Phase 1 test matrix.

The .set files in this directory are GENERATED. Editing one by hand is how a
study quietly ends up testing something other than what it pre-registered, so
tests/run_tests.sh regenerates them into a temp directory and fails if the
committed files differ.

    python3 MQL5/Presets/generate_presets.py            # rewrite the .set files
    python3 MQL5/Presets/generate_presets.py --check    # verify, change nothing
"""
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent

# EnSlMode
SL_NONE, SL_OPPOSITE_ZONE = 0, 1
# EnRunMode
RUN_RESEARCH, RUN_TZ_DIAGNOSTIC = 0, 1
# EnServerTz
SRVTZ_EU_DST, SRVTZ_FIXED = 0, 1

# ---------------------------------------------------------------- matrix ----
# (id, cutoff h, cutoff m, sl mode, max reversals, magic, description)
MATRIX = [
    ("A1", 9, 30, SL_OPPOSITE_ZONE, 0, 8550011,
     "PRIMARY BASELINE: first breakout only, TP 1.0x range, SL at the opposite "
     "zone edge, hard exit 09:30 Warsaw"),
    ("A2", 10, 0, SL_OPPOSITE_ZONE, 0, 8550012,
     "As A1 with the hard exit moved to 10:00 Warsaw"),
    ("B1", 9, 30, SL_NONE, 0, 8550021,
     "SOURCE-LIKE NO-FIXED-SL DIAGNOSTIC: first breakout only, TP 1.0x range, "
     "no fixed SL, hard exit 09:30 Warsaw"),
    ("B2", 10, 0, SL_NONE, 0, 8550022,
     "As B1 with the hard exit moved to 10:00 Warsaw"),
    ("C1", 9, 30, SL_NONE, 1, 8550031,
     "DOUBLE-BREAKOUT DIAGNOSTIC: enter the first breakout, reverse once if the "
     "opposite zone edge breaks, hard exit 09:30 Warsaw"),
    ("C2", 10, 0, SL_NONE, 1, 8550032,
     "As C1 with the hard exit moved to 10:00 Warsaw"),
]


def settings(cfg_id, cut_h, cut_m, sl_mode, max_rev, magic, run_mode=RUN_RESEARCH):
    return [
        ("InpRunMode", run_mode),
        ("InpConfigId", cfg_id),
        ("InpRequireSymbolSubstring", ""),
        ("InpZoneStartHour", 8),
        ("InpZoneStartMinute", 55),
        ("InpZoneEndHour", 9),
        ("InpZoneEndMinute", 0),
        ("InpCutoffHour", cut_h),
        ("InpCutoffMinute", cut_m),
        ("InpTpMultiplier", "1.0"),
        ("InpSlMode", sl_mode),
        ("InpMaxReversals", max_rev),
        ("InpSkipEntryOnOvershoot", "true"),
        ("InpServerTzMode", SRVTZ_EU_DST),
        ("InpServerBaseUtcOffsetHrs", 2),
        ("InpVolume", "0.0"),
        ("InpMagic", magic),
        ("InpDeviationPoints", 100),
        ("InpWriteCsv", "true"),
        ("InpCsvToCommonFolder", "true"),
        ("InpCsvPrefix", "daxDzida"),
        ("InpVerboseLog", "false"),
    ]


def render(cfg_id, description, pairs):
    lines = [
        "; daxDzida Phase 1 pre-registered configuration " + cfg_id,
        "; " + description,
        ";",
        "; GENERATED FILE - edit MQL5/Presets/generate_presets.py instead.",
        "; Load in the MT5 Strategy Tester: Inputs tab -> Load.",
        "",
    ]
    lines += [f"{k}={v}" for k, v in pairs]
    return "\n".join(lines) + "\n"


def build():
    out = {}
    for cfg_id, cut_h, cut_m, sl_mode, max_rev, magic, desc in MATRIX:
        out[f"{cfg_id}.set"] = render(
            cfg_id, desc, settings(cfg_id, cut_h, cut_m, sl_mode, max_rev, magic))

    out["TZDIAG.set"] = render(
        "TZDIAG",
        "TIMEZONE DIAGNOSTIC: places no orders. Run this FIRST to establish how "
        "broker server timestamps map to UTC and Europe/Warsaw.",
        settings("TZDIAG", 9, 30, SL_OPPOSITE_ZONE, 0, 8550001,
                 run_mode=RUN_TZ_DIAGNOSTIC))
    return out


def main():
    check = "--check" in sys.argv
    files = build()
    failed = False
    for name, content in files.items():
        path = HERE / name
        if check:
            current = path.read_text(encoding="utf-8") if path.exists() else None
            if current != content:
                print(f"FAIL: {name} does not match the generator")
                failed = True
        else:
            path.write_text(content, encoding="utf-8")
            print(f"wrote {name}")
    if check:
        print("RESULT: FAIL" if failed else f"  {len(files)} presets match the pre-registered matrix")
        return 1 if failed else 0
    return 0


if __name__ == "__main__":
    sys.exit(main())
