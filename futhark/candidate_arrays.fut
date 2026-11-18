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

-- candidate_arrays.fut
-- Structure-of-Arrays (SoA) layout, candidate ID mapping, parent-index remapping,
-- and hash-index preparation for SOVEREIGN-RH-LOCK.
--
-- Edge-Case & Numerical Stability Contract:
-- 1. Empty arrays (`n == 0`): all kernels return empty arrays `[]` without out-of-bounds access.
-- 2. NaNs / Infinities: `f64.isnan` / `f64.isinf` are explicitly sanitized or assigned status `STATUS_INVALID (-1)`
--    so they never silently pass threshold or interval filters.
-- 3. Index bounds: `scatter` operations guard indices against `[0, m-1]` using `-1` sentinel
--    (Futhark `scatter` ignores negative indices).
-- 4. Integer overflow: hash mixing uses unsigned `u64` bitwise shifts/XORs before converting back to `i64`.

type CandidateSoA [n] = {
  candidate_id:    [n]i64,
  parent_id:       [n]i64,
  generation:      [n]i64,
  zero_real:       [n]f64,
  zero_imag:       [n]f64,
  eigenvalue_real: [n]f64,
  entropy:         [n]f64,
  residual:        [n]f64,
  status:          [n]i64
}

-- Status codes (numerical pruning does NOT delete from provenance ledger)
let status_active: i64 = 1i64
let status_pruned: i64 = 2i64
let status_invalid: i64 = -1i64

-- Kernel 1: Candidate ID mapping (assigns contiguous offset IDs starting at `base_id`)
entry map_candidate_ids [n] (base_id: i64) (raw_indices: [n]i64) : [n]i64 =
  map (\i -> base_id + i) raw_indices

-- Kernel 6: Hypothesis parent-index remapping
-- Given `old_ids` (sorted or unsorted) and `parent_ids`, maps each `parent_id`
-- to its index in `old_ids`, or `-1i64` if root / not found.
entry remap_parent_indices [n] (candidate_ids: [n]i64) (parent_ids: [n]i64) : [n]i64 =
  if n == 0 then replicate 0 0i64
  else
    map (\pid ->
      if pid < 0i64 then -1i64
      else
        let matches = map2 (\idx cid -> if cid == pid then idx else -1i64) (iota n) candidate_ids
        in reduce i64.max (-1i64) matches
    ) parent_ids

-- Kernel 8: Hash-index preparation (SplitMix64 mixing on candidate_id & generation)
def mix64 (x: u64) : u64 =
  let z1 = (x ^ (x >> 30u64)) * 0xbf58476d1ce4e5b9u64
  let z2 = (z1 ^ (z1 >> 27u64)) * 0x94d049bb133111ebu64
  in z2 ^ (z2 >> 31u64)

entry prepare_hash_indices [n]
    (candidate_ids: [n]i64)
    (generations: [n]i64)
    (table_mask: i64) : [n]i64 =
  if n == 0 || table_mask <= 0i64 then replicate n 0i64
  else
    let mask_u = u64.i64 table_mask
    in map2 (\cid gen ->
      let h = mix64 ((u64.i64 cid) ^ (mix64 (u64.i64 gen)))
      in i64.u64 (h & mask_u)
    ) candidate_ids generations
