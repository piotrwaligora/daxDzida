#!/usr/bin/env bash
# Full deterministic test suite for the daxDzida Phase 1 research logic.
#
#   ./tests/run_tests.sh
#
# 1. compiles the same DzTime.mqh / DzCore.mqh sources that MetaEditor compiles
#    and runs the behavioural regression tests
# 2. statically checks that the research CSV header and data row agree
# 3. verifies the committed .set presets still match the pre-registered matrix
#
# The mutation check (tests/mutation_check.sh) is deliberately separate: it is
# slower and is only needed when the suite itself is being changed.
set -euo pipefail
cd "$(dirname "$0")"

echo "[1/3] behavioural regression tests"
mkdir -p build
g++ -std=c++11 -O1 -Wall -Wextra -Wno-unused-parameter \
    -o build/test_dz test_dz.cpp
./build/test_dz

echo
echo "[2/3] research CSV schema check"
python3 check_csv_columns.py

echo
echo "[3/3] pre-registered preset check"
python3 ../MQL5/Presets/generate_presets.py --check
