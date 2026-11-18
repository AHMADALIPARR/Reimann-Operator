# Copyright (C) 2026 Ahmad Ali Parr / SnapKitty Research Lab
# 
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

"""Entropy primitives for SOVEREIGN-RH-LOCK.

Strictly separates:
1. Von Neumann entropy S(rho) = -Tr(rho log rho) for valid density operators.
2. Shannon entropy H(p) = -sum_i p_i log p_i for probability distributions.
Never interchange S(rho), H(p), and r(s) = |zeta(s)|.
"""

from __future__ import annotations

import math
import sys
from pathlib import Path
from typing import Any

import numpy as np

_REPO_ROOT = str(Path(__file__).resolve().parents[1])
_saved_path = list(sys.path)
try:
    sys.path = [p for p in sys.path if p not in ("", _REPO_ROOT)]
    import torch as _torch  # type: ignore

    if hasattr(_torch, "set_default_dtype") and hasattr(_torch, "Tensor"):
        _torch.set_default_dtype(_torch.float64)
        HAS_TORCH = True
    else:
        _torch = None  # type: ignore
        HAS_TORCH = False
except ImportError:
    _torch = None  # type: ignore
    HAS_TORCH = False
finally:
    sys.path = _saved_path


def spectral_entropy(probabilities: Any) -> Any:
    """Shannon entropy H(p) = -sum p_i log p_i of normalized probabilities."""
    if HAS_TORCH and isinstance(probabilities, _torch.Tensor):
        if probabilities.numel() == 0:
            raise ValueError("probabilities tensor must be non-empty")
        total = probabilities.sum(dim=-1, keepdim=True)
        if _torch.any(total <= 0):
            raise ValueError("probabilities must sum to a positive value")
        p = probabilities / total
        p = p.clamp_min(_torch.finfo(p.dtype).tiny)
        return -(p * p.log()).sum(dim=-1)

    arr = np.asarray(probabilities, dtype=np.float64)
    if arr.size == 0:
        raise ValueError("probabilities array must be non-empty")
    if np.any(arr < 0) or not np.all(np.isfinite(arr)):
        raise ValueError("probabilities must be finite and non-negative")
    total = np.sum(arr, axis=-1, keepdims=True)
    if np.any(total <= 0):
        raise ValueError("probabilities must sum to a positive value")
    p = arr / total
    p = np.clip(p, np.finfo(np.float64).tiny, None)
    return -np.sum(p * np.log(p), axis=-1)


def shannon_entropy(probabilities: Any) -> Any:
    """Explicit alias for Shannon entropy H(p) of hypothesis distributions."""
    return spectral_entropy(probabilities)


def von_neumann_entropy(density_operator: Any, tol: float = 1e-10) -> float:
    """Compute S(rho) = -Tr(rho log rho) for a valid density operator rho.

    Validates:
    - Square 2D matrix
    - Hermitian: ||rho - rho*||_F <= tol
    - Positive semidefinite: min eigenvalue >= -tol
    - Normalized trace: |Tr(rho) - 1| <= tol
    """
    if HAS_TORCH and isinstance(density_operator, _torch.Tensor):
        rho = density_operator.detach().cpu().numpy().astype(np.complex128)
    else:
        rho = np.asarray(density_operator, dtype=np.complex128)

    if rho.ndim != 2 or rho.shape[0] != rho.shape[1] or rho.shape[0] == 0:
        raise ValueError("density_operator must be a non-empty square matrix")

    herm_err = float(np.linalg.norm(rho - rho.conj().T, ord="fro"))
    if herm_err > tol:
        raise ValueError(f"density_operator is not Hermitian (residual={herm_err:.3e})")

    rho_herm = 0.5 * (rho + rho.conj().T)
    tr = float(np.real(np.trace(rho_herm)))
    if abs(tr - 1.0) > tol:
        raise ValueError(f"density_operator trace must be 1.0 (got {tr:.12f})")

    evals = np.linalg.eigvalsh(rho_herm)
    min_ev = float(np.min(evals))
    if min_ev < -tol:
        raise ValueError(f"density_operator is not positive semidefinite (min_eig={min_ev:.3e})")

    pos = evals[evals > 0.0]
    if pos.size == 0:
        return 0.0
    return float(-np.sum(pos * np.log(pos)))


def entropy_bounds_check(entropy_val: float, dim: int) -> bool:
    """Verify 0 <= S <= log(dim) within floating-point tolerance."""
    if dim <= 0 or not math.isfinite(entropy_val):
        return False
    return -1e-12 <= entropy_val <= math.log(dim) + 1e-12
