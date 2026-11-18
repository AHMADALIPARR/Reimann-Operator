#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-SnapKitty-Opaque-1.0
# Copyright (C) 2026 Ahmad Ali Parr / SnapKitty Research Lab
# usage: run_case.sh RO NAME RTOL ATOL COMMAND ARGS...  (run from the repo root)
# Runs `ro COMMAND ARGS...` and compares its output with the golden line <NAME> in
# tests/golden/ro_golden.txt (exact when RTOL = ATOL = 0).
set -u
ro=$1; name=$2; rtol=$3; atol=$4; shift 4
exp=$(mktemp); out=$(mktemp)
grep -m1 "^$name " tests/golden/ro_golden.txt | cut -d' ' -f2- > "$exp"
if [ ! -s "$exp" ]; then echo "no golden line for $name"; exit 1; fi
"$ro" "$@" > "$out" 2>/dev/null
"$ro" cmp "$exp" "$out" "$rtol" "$atol"
rc=$?
rm -f "$exp" "$out"
exit $rc
