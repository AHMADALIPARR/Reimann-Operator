-- SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-SnapKitty-Opaque-1.0
-- Copyright (C) 2026 Ahmad Ali Parr / SnapKitty Research Lab
-- Cherry-picked from AHMADALIPARR/riemann-gas lean/DMZ_F2_Decomposition.lean @ be609fa.
-- WeilBound, weil_bound_exists and weil_bound_genus_two, byte-for-byte.

import Mathlib.Data.Nat.Basic

def WeilBound (g : ℕ) : ℕ :=
  2 ^ g + 1 + g * 2 ^ (g / 2 + 1)

theorem weil_bound_exists (g : ℕ) : ∃ (bound : ℕ), bound = WeilBound g :=
  ⟨WeilBound g, rfl⟩

theorem weil_bound_genus_two : WeilBound 2 = 13 := by native_decide
