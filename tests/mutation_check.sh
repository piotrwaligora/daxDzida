#!/usr/bin/env bash
# Sanity check that the regression suite is not vacuous: deliberately break
# one critical behaviour at a time and confirm the suite goes red.
# Nothing in the working tree is modified - everything happens in a temp copy.
set -uo pipefail
cd "$(dirname "$0")/.."
ROOT="$(pwd)"
PASS=0
FAIL=0

run_mutant() {
  local name="$1"; shift
  local file="$1"; shift
  local pattern="$1"; shift
  local replace="$1"; shift

  local tmp; tmp="$(mktemp -d)"
  cp -r "$ROOT/MQL5" "$ROOT/tests" "$tmp/" 2>/dev/null
  rm -rf "$tmp/tests/build"
  if ! grep -qF -- "$pattern" "$tmp/$file"; then
    echo "  SKIP  $name  (pattern not found: $pattern)"
    rm -rf "$tmp"; FAIL=$((FAIL+1)); return
  fi
  python3 - "$tmp/$file" "$pattern" "$replace" <<'PY'
import sys
p, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(p).read()
open(p, 'w').write(s.replace(old, new, 1))
PY
  ( cd "$tmp/tests" && g++ -std=c++11 -O1 -o /tmp/mutant_$$ test_dz.cpp 2>/dev/null ) || {
    echo "  SKIP  $name  (mutant did not compile)"; rm -rf "$tmp"; FAIL=$((FAIL+1)); return; }
  if /tmp/mutant_$$ >/dev/null 2>&1; then
    echo "  NOT CAUGHT  $name"
    FAIL=$((FAIL+1))
  else
    echo "  caught      $name"
    PASS=$((PASS+1))
  fi
  rm -f /tmp/mutant_$$; rm -rf "$tmp"
}

echo "mutation check - every mutant below MUST make the suite fail"
echo "============================================================"

run_mutant "zone starts at 08:50 instead of 08:55" \
  MQL5/Include/daxDzida/DzCore.mqh \
  "c.zoneStartMs          = 8 * DZ_MS_PER_HOUR + 55 * DZ_MS_PER_MIN;" \
  "c.zoneStartMs          = 8 * DZ_MS_PER_HOUR + 50 * DZ_MS_PER_MIN;"

run_mutant "zone freezes at 09:01 instead of 09:00" \
  MQL5/Include/daxDzida/DzCore.mqh \
  "c.zoneEndMs            = 9 * DZ_MS_PER_HOUR;" \
  "c.zoneEndMs            = 9 * DZ_MS_PER_HOUR + 1 * DZ_MS_PER_MIN;"

run_mutant "breakout uses >= instead of > (touch counts as break)" \
  MQL5/Include/daxDzida/DzCore.mqh \
  "         if(bid > s.zoneHigh)
            dir = DZ_DIR_LONG;" \
  "         if(bid >= s.zoneHigh)
            dir = DZ_DIR_LONG;"

run_mutant "LONG fills at BID instead of ASK" \
  MQL5/Include/daxDzida/DzCore.mqh \
  "   double entryPx = (dir == DZ_DIR_LONG ? ask : bid);" \
  "   double entryPx = (dir == DZ_DIR_LONG ? bid : bid);"

run_mutant "SHORT TP evaluated on BID instead of ASK" \
  MQL5/Include/daxDzida/DzCore.mqh \
  "         bool hitTp = (s.legDir == DZ_DIR_LONG) ? (bid >= s.tpLong) : (ask <= s.tpShort);" \
  "         bool hitTp = (s.legDir == DZ_DIR_LONG) ? (bid >= s.tpLong) : (bid <= s.tpShort);"

run_mutant "zone built from ASK instead of BID" \
  MQL5/Include/daxDzida/DzCore.mqh \
  "            if(bid > s.zoneHigh) s.zoneHigh = bid;" \
  "            if(ask > s.zoneHigh) s.zoneHigh = ask;"

run_mutant "TP multiplier applied twice" \
  MQL5/Include/daxDzida/DzCore.mqh \
  "   s.tpLong    = s.zoneHigh + s.zoneRange * cfg.tpMult;" \
  "   s.tpLong    = s.zoneHigh + s.zoneRange * cfg.tpMult * 2.0;"

run_mutant "TP checked before SL (optimistic ordering)" \
  MQL5/Include/daxDzida/DzCore.mqh \
  "      // 1. stop loss first (pessimistic ordering)
      if(s.inTrade && s.slEnabled)" \
  "      // 1. stop loss first (pessimistic ordering)
      if(false && s.inTrade && s.slEnabled)"

run_mutant "unlimited reversals" \
  MQL5/Include/daxDzida/DzCore.mqh \
  "      if(s.inTrade && todMs < cfg.cutoffMs && s.reversalCount < cfg.maxReversals)" \
  "      if(s.inTrade && todMs < cfg.cutoffMs && cfg.maxReversals > 0)"

run_mutant "cutoff ignored" \
  MQL5/Include/daxDzida/DzCore.mqh \
  "      if(s.inTrade && todMs >= cfg.cutoffMs)" \
  "      if(false && s.inTrade && todMs >= cfg.cutoffMs)"

run_mutant "entry overshoot silently accepted" \
  MQL5/Include/daxDzida/DzCore.mqh \
  "      if(cfg.skipEntryOnOvershoot)" \
  "      if(false)"

run_mutant "Warsaw treated as a fixed UTC+1 (no DST)" \
  MQL5/Include/daxDzida/DzTime.mqh \
  "   return (DzIsEuSummerTime(utcSec) ? 7200 : 3600);" \
  "   return 3600;"

run_mutant "EU DST switches on the last Saturday instead of Sunday" \
  MQL5/Include/daxDzida/DzTime.mqh \
  "   return d - (long)dow;" \
  "   return d - (long)dow - 1;"

run_mutant "look-ahead: zone ticks may open a trade" \
  MQL5/Include/daxDzida/DzCore.mqh \
  "         s.zoneLastTickMsc = warsawMsc;
         return;" \
  "         s.zoneLastTickMsc = warsawMsc;"

echo "============================================================"
echo "mutants caught: $PASS   not caught / skipped: $FAIL"
[ "$FAIL" -eq 0 ]
