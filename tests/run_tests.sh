#!/usr/bin/env bash
# Full deterministic test suite for the daxDzida Phase 1 research logic.
#
#   ./tests/run_tests.sh
#
# 1. compiles the same DzTime.mqh / DzCore.mqh sources that MetaEditor compiles
#    and runs the behavioural regression tests
# 2. pre-flight parses the real EA source against MT5 API stubs, so ordinary
#    MQL5 compile failures are caught without a Windows round trip
# 3. statically checks that the research CSV header and data row agree
# 4. verifies the committed .set presets still match the pre-registered matrix
#
# Two checks live outside this script because they are slower or need another
# platform:
#   tests/mutation_check.sh        - proves this suite is not vacuous
#   tools/Test-MetaEditorLog.ps1   - MetaEditor log parser tests (PowerShell)
set -euo pipefail
cd "$(dirname "$0")"

echo "[1/4] behavioural regression tests"
mkdir -p build
g++ -std=c++11 -O1 -Wall -Wextra -Wno-unused-parameter \
    -o build/test_dz test_dz.cpp
./build/test_dz

echo
echo "[2/4] MQL5 EA pre-flight syntax check"
python3 mql5_syntax_check.py

echo
echo "[3/4] research CSV schema check"
python3 check_csv_columns.py

echo
echo "[4/4] pre-registered preset check"
python3 ../MQL5/Presets/generate_presets.py --check
