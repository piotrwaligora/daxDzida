#!/usr/bin/env python3
"""Pre-flight syntax check for the MQL5 Expert Advisor.

MetaEditor only runs on Windows. This mechanically rewrites the *real* EA
source into something g++ can parse, against the API stubs in
tests/shim/mt5_api_shim.h, and reports the ordinary compile failures --
typos, unbalanced braces, undeclared identifiers, wrong argument counts,
wrong return types -- without a Windows round trip.

It does NOT replace MetaEditor. It cannot check `input` / `input group`
syntax, `#property` directives, MQL5's requirement that structs be passed by
reference, or MQL5's own conversion warnings. Green here means "worth
compiling", never "compiles".

The EA source is never modified; the rewrite happens in a temp file.

    python3 tests/mql5_syntax_check.py [--keep]
"""
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
EA = ROOT / "MQL5" / "Experts" / "daxDzida" / "DaxDzida_Phase1.mq5"
SHIM = ROOT / "tests" / "shim" / "mt5_api_shim.h"
INCLUDE_ROOT = ROOT / "MQL5" / "Include"

# `#include <daxDzida/DzCore.mqh>`  ->  absolute path to the real header
ANGLE_INCLUDE = re.compile(r'^\s*#include\s*<([^>]+)>\s*$')
# `input group "..."` (MQL5-only UI grouping, no C++ equivalent)
INPUT_GROUP = re.compile(r'^\s*(?:s)?input\s+group\b.*$')
# `input int Foo = 1;` -> `static int Foo = 1;`
INPUT_DECL = re.compile(r'^(\s*)(?:s)?input\s+')
PROPERTY = re.compile(r'^\s*#property\b')


def translate(src: str) -> str:
    out = []
    for line in src.splitlines():
        if PROPERTY.match(line):
            out.append("// [shim] " + line.strip())
            continue
        if INPUT_GROUP.match(line):
            out.append("// [shim] " + line.strip())
            continue

        m = ANGLE_INCLUDE.match(line)
        if m:
            target = m.group(1)
            if target.lower().startswith("trade/"):
                # provided by the API shim
                out.append("// [shim] " + line.strip())
                continue
            resolved = INCLUDE_ROOT / target
            if not resolved.exists():
                out.append("// [shim] UNRESOLVED " + line.strip())
                print(f"  WARNING: could not resolve #include <{target}>")
                continue
            out.append(f'#include "{resolved}"')
            continue

        out.append(INPUT_DECL.sub(r"\1static ", line))
    return "\n".join(out) + "\n"


def main() -> int:
    keep = "--keep" in sys.argv

    if shutil.which("g++") is None:
        print("  SKIP: g++ not available, MQL5 pre-flight syntax check not run")
        return 0
    for p in (EA, SHIM):
        if not p.exists():
            print(f"FAIL: missing {p}")
            return 1

    tmpdir = Path(tempfile.mkdtemp(prefix="dz_mql5_"))
    gen = tmpdir / "ea_translated.cpp"
    gen.write_text(
        f'#include "{SHIM}"\n'
        f"// ---- translated from {EA.name} ----\n" + translate(EA.read_text(encoding="utf-8", errors="replace")),
        encoding="utf-8",
    )

    proc = subprocess.run(
        ["g++", "-fsyntax-only", "-std=c++11", "-Wall", "-Wextra",
         "-Wno-unused-parameter", "-Wno-unused-function", "-Wno-unused-variable",
         "-x", "c++", str(gen)],
        capture_output=True, text=True,
    )

    diag = (proc.stderr or "").strip()
    errors = [l for l in diag.splitlines() if " error:" in l]
    warnings = [l for l in diag.splitlines() if " warning:" in l]

    if errors:
        print(f"  {len(errors)} error(s) parsing the EA source:")
        for line in diag.splitlines():
            print("    " + line.replace(str(tmpdir) + "/", ""))
    elif warnings:
        print(f"  parsed cleanly, {len(warnings)} warning(s):")
        for line in warnings:
            print("    " + line.replace(str(tmpdir) + "/", ""))
    else:
        print("  EA source parses cleanly against the MT5 API stubs")

    if keep:
        print(f"  translated source kept at {gen}")
    else:
        shutil.rmtree(tmpdir, ignore_errors=True)

    ok = not errors
    print("RESULT: PASS" if ok else "RESULT: FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
