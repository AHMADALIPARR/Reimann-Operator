-- Copyright (C) 2026 Ahmad Ali Parr / SnapKitty Research Lab
-- 
-- This program is free software: you can redistribute it and/or modify
-- it under the terms of the GNU Affero General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.
--
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU Affero General Public License for more details.
--
-- You should have received a copy of the GNU Affero General Public License
-- along with this program.  If not, see <https://www.gnu.org/licenses/>.

-- recursive_prune.fut
-- Recursive candidate compaction, mask-based pruning, ordered segment reduction,
-- and entropy-weighted priority calculations.
--
-- Numerical pruning is strictly a search-budget filter; pruned candidates remain
-- recorded in the external provenance ledger with status = 2.

-- Kernel 2: Recursive candidate compaction (stream compaction via scan + scatter)
-- Keeps elements where `keep_mask[i] == true`.
-- Empty array behavior: returns empty arrays of length 0.
entry compact_candidates [n]
    (keep_mask: [n]bool)
    (candidate_id: [n]i64)
    (parent_id: [n]i64)
    (generation: [n]i64)
    (zero_real: [n]f64)
    (zero_imag: [n]f64)
    (eigenvalue_real: [n]f64)
    (entropy: [n]f64)
    (residual: [n]f64)
    (status: [n]i64) : ([]i64, []i64, []i64, []f64, []f64, []f64, []f64, []f64, []i64) =
  if n == 0 then
    ([], [], [], [], [], [], [], [], [])
  else
    let flags = map (\b -> if b then 1i64 else 0i64) keep_mask
    let offsets = scan (+) 0i64 flags
    let total = offsets[n - 1]
    let dest = map2 (\f off -> if f == 1i64 then off - 1i64 else -1i64) flags offsets
    in ( scatter (replicate total 0i64) dest candidate_id
       , scatter (replicate total 0i64) dest parent_id
       , scatter (replicate total 0i64) dest generation
       , scatter (replicate total 0.0f64) dest zero_real
       , scatter (replicate total 0.0f64) dest zero_imag
       , scatter (replicate total 0.0f64) dest eigenvalue_real
       , scatter (replicate total 0.0f64) dest entropy
       , scatter (replicate total 0.0f64) dest residual
       , scatter (replicate total 0i64) dest status
       )

-- Kernel 3: Mask-based pruning (marks status = 2 for pruned, -1 for NaN/Inf)
entry mask_prune_status [n]
    (status: [n]i64)
    (entropy: [n]f64)
    (residual: [n]f64)
    (max_residual: f64)
    (min_entropy: f64) : [n]i64 =
  map3 (\st ent res ->
    if f64.isnan ent || f64.isinf ent || f64.isnan res || f64.isinf res then
      -1i64
    else if st != 1i64 then
      st
    else if res > max_residual || ent < min_entropy then
      2i64
    else
      1i64
  ) status entropy residual

-- Kernel 4: Ordered segment reduction (max score per segment, e.g. per generation)
-- `flags[i]` is `true` at the start of each contiguous segment.
-- Uses associative segmented scan (`(flag, val)` monoid) to avoid unstable floating-point sums.
entry ordered_segment_max_f64 [n] (flags: [n]bool) (values: [n]f64) : [n]f64 =
  if n == 0 then replicate 0 0.0f64
  else
    let sanitized = map (\v -> if f64.isnan v then -f64.inf else v) values
    let pairs = zip flags sanitized
    let scanned = scan (\(f1, v1) (f2, v2) ->
      if f2 then (true, v2) else (f1, f64.max v1 v2)
    ) (true, -f64.inf) pairs
    in map (.1) scanned

-- Kernel 7: Entropy-weighted priority calculation:
--   J(C) = w1 * info_gain + w2 * novelty + w3 * obligation_progress - w4 * penalty
-- Guards against NaN/Inf by returning `-f64.inf` for non-finite inputs.
entry compute_entropy_priority [n]
    (entropy: [n]f64)
    (novelty: [n]f64)
    (obligation_progress: [n]f64)
    (residual: [n]f64)
    (w1: f64) (w2: f64) (w3: f64) (w4: f64) : [n]f64 =
  map4 (\ent nov prog res ->
    if f64.isnan ent || f64.isinf ent || f64.isnan nov || f64.isinf nov ||
       f64.isnan prog || f64.isinf prog || f64.isnan res || f64.isinf res then
      -f64.inf
    else
      w1 * ent + w2 * nov + w3 * prog - w4 * res
  ) entropy novelty obligation_progress residual
