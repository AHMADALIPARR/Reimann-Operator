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

-- spectral_filter.fut
-- Spectral interval filtering and residual threshold comparisons.
--
-- Explicitly handles empty arrays, NaNs, and infinities:
-- Non-finite `eigenvalue_real`, `zero_real`, `zero_imag`, or `residual` always
-- evaluate to `false` in filter predicates.

-- Kernel 5: Spectral interval filtering
-- Returns indices / mask of candidates with `low <= eigenvalue_real <= high`.
entry spectral_interval_mask [n]
    (eigenvalue_real: [n]f64)
    (low: f64)
    (high: f64) : [n]bool =
  if f64.isnan low || f64.isnan high || low > high then
    replicate n false
  else
    map (\lam ->
      !(f64.isnan lam) && !(f64.isinf lam) && lam >= low && lam <= high
    ) eigenvalue_real

entry filter_spectral_interval [n]
    (eigenvalue_real: [n]f64)
    (low: f64)
    (high: f64) : []f64 =
  let mask = spectral_interval_mask eigenvalue_real low high
  let pairs = filter (.0) (zip mask eigenvalue_real)
  in map (.1) pairs

-- Kernel 9: Residual threshold comparison
-- Checks `|zeta(s)| <= tol` AND `|Re(s) - 0.5| <= line_tol`.
-- Passing this numerical filter is Gate 7 screening ONLY, never a proof of RH.
entry residual_threshold_mask [n]
    (zero_real: [n]f64)
    (residual: [n]f64)
    (tol: f64)
    (line_tol: f64) : [n]bool =
  if f64.isnan tol || f64.isnan line_tol || tol < 0.0f64 || line_tol < 0.0f64 then
    replicate n false
  else
    map2 (\zr res ->
      !(f64.isnan zr) && !(f64.isinf zr) &&
      !(f64.isnan res) && !(f64.isinf res) &&
      res <= tol && f64.abs (zr - 0.5f64) <= line_tol
    ) zero_real residual
