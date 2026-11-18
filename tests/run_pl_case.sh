#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-SnapKitty-Opaque-1.0
# Copyright (C) 2026 Ahmad Ali Parr / SnapKitty Research Lab
# usage: run_pl_case.sh SWIPL NAME SCRIPT ARGS...  (run from the repo root)
# Runs the Prolog port and requires byte-identical output to section NAME of
# tests/golden/prolog_golden.txt.
set -u
swipl=$1; name=$2; shift 2
exp=$(mktemp); out=$(mktemp)
awk -v n="=== $name" '$0 == n {on=1; next} /^=== / {on=0} on' tests/golden/prolog_golden.txt > "$exp"
if [ ! -s "$exp" ]; then echo "no golden section for $name"; exit 1; fi
"$swipl" "$@" > "$out"
if ! cmp -s "$exp" "$out"; then diff "$exp" "$out" | head -20; rm -f "$exp" "$out"; exit 1; fi
rm -f "$exp" "$out"
