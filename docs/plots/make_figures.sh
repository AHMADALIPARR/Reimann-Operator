#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-SnapKitty-Opaque-1.0
# Copyright (C) 2026 Ahmad Ali Parr / SnapKitty Research Lab
#
# Regenerates docs/images/*.svg from the repository's own data and tools.
# usage (from the repo root): sh docs/plots/make_figures.sh build/ro
# Needs a POSIX awk and swipl on PATH.
set -eu
RO=${1:-build/ro}
P=docs/plots
OUT=docs/images
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$OUT"
awk -f $P/zeros_line.awk data/zeta_zeros_oracle.txt > $OUT/zeros_critical_line.svg
awk -f $P/spacing_gue.awk data/zeta_zeros_oracle.txt > $OUT/spacing_gue.svg
for n in 32 64 128; do
  "$RO" bk $n 1.0 10.0 0.0 > "$TMP/bk$n.json"
  "$RO" eigvalsh "$TMP/bk$n.json" > "$TMP/ev$n.json"
done
awk -v labels="BK n = 32,BK n = 64,BK n = 128" -v tmax=60 -f $P/bk_vs_zeros.awk \
  "$TMP/ev32.json" "$TMP/ev64.json" "$TMP/ev128.json" data/zeta_zeros_oracle.txt > $OUT/bk_vs_zeros.svg
awk -f $P/architecture.awk $P/architecture.txt > $OUT/architecture.svg
swipl $P/ontology_graph.pl owl/rh_ontology.ttl > $OUT/ontology_classes.svg 2>/dev/null
ls -l $OUT
