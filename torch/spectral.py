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

"""Spectral operator analysis and high-precision zeta zero residual verification."""

from __future__ import annotations

import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, Tuple

import mpmath as mp
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


def hermitian_residual(operator: Any) -> Any:
    """Compute Frobenius norm ||D - D*||_F."""
    if HAS_TORCH and isinstance(operator, _torch.Tensor):
        return _torch.linalg.matrix_norm(operator - operator.conj().transpose(-2, -1))
    arr = np.asarray(operator, dtype=np.complex128)
    return float(np.linalg.norm(arr - np.swapaxes(arr.conj(), -2, -1), ord="fro"))


def spectral_candidates(operator: Any) -> Any:
    """Compute real eigenvalues of a Hermitian operator."""
    if HAS_TORCH and isinstance(operator, _torch.Tensor):
        return _torch.linalg.eigvalsh(operator)
    arr = np.asarray(operator, dtype=np.complex128)
    return np.linalg.eigvalsh(arr)


def build_berry_keating_discretization(n: int, a: float = 1.0, b: float = 10.0, theta: float = 0.0) -> np.ndarray:
    """Construct a finite-difference Hermitian discretization of H_BK = -i(x d/dx + 1/2)
    on [a, b] with twisted periodic boundary condition b^(1/2) psi(b) = e^(i*theta) a^(1/2) psi(a).
    """
    if n < 4:
        raise ValueError("Discretization size n must be >= 4")
    if a <= 0.0 or b <= a:
        raise ValueError("Require 0 < a < b")

    length = np.log(b / a)
    du = length / n
    mat = np.zeros((n, n), dtype=np.complex128)
    inv_2du = 1.0 / (2.0 * du)

    for j in range(n):
        j_next = (j + 1) % n
        j_prev = (j - 1) % n
        phase_fwd = np.exp(1j * theta) if j == n - 1 else 1.0
        phase_bwd = np.exp(-1j * theta) if j == 0 else 1.0
        mat[j, j_next] += -1j * inv_2du * phase_fwd
        mat[j, j_prev] += 1j * inv_2du * phase_bwd

    return 0.5 * (mat + mat.conj().T)


def zeta_residual(sigma: float, t: float, dps: int = 50) -> Tuple[float, float]:
    """Compute r(s) = |zeta(sigma + i*t)| at `dps` decimal digits of precision."""
    mp.mp.dps = dps
    s = mp.mpc(mp.mpf(str(sigma)), mp.mpf(str(t)))
    val = mp.zeta(s)
    res = float(abs(val))
    uncertainty = float(mp.power(10, -(dps - 5)))
    return res, uncertainty


def verify_critical_zero_reference(index_k: int, dps: int = 50) -> Dict[str, float]:
    """Retrieve the k-th nontrivial zeta zero via mpmath.zetazero and verify its residual."""
    if index_k < 1:
        raise ValueError("Zero index k must be >= 1")
    mp.mp.dps = dps
    rho = mp.zetazero(index_k)
    val = mp.zeta(rho)
    return {
        "index": float(index_k),
        "real": float(mp.re(rho)),
        "imag": float(mp.im(rho)),
        "residual": float(abs(val)),
        "dps": float(dps),
    }


def spectral_spacing_statistics(eigenvalues: np.ndarray) -> Dict[str, float]:
    """Compute nearest-neighbor spacing mean, variance, and consecutive spacing ratio <r>."""
    ev = np.sort(np.asarray(eigenvalues, dtype=np.float64))
    if ev.size < 3:
        return {"count": float(ev.size), "mean_spacing": 0.0, "std_spacing": 0.0, "mean_ratio": 0.0}
    spacings = np.diff(ev)
    pos = spacings[spacings > 1e-15]
    if pos.size < 2:
        return {
            "count": float(ev.size),
            "mean_spacing": float(np.mean(spacings)),
            "std_spacing": float(np.std(spacings)),
            "mean_ratio": 0.0,
        }
    ratios = np.minimum(pos[:-1], pos[1:]) / np.maximum(pos[:-1], pos[1:])
    return {
        "count": float(ev.size),
        "mean_spacing": float(np.mean(spacings)),
        "std_spacing": float(np.std(spacings)),
        "mean_ratio": float(np.mean(ratios)),
    }


@dataclass
class PerturbationResult:
    epsilon: float
    max_eigenvalue_shift: float
    weyl_upper_bound: float
    bound_satisfied: bool


def adversarial_perturbation_test(
    operator: np.ndarray, epsilon: float = 1e-6, seed: int = 42
) -> PerturbationResult:
    """Verify Weyl's eigenvalue stability inequality |lam_k(D+E) - lam_k(D)| <= ||E||_2."""
    rng = np.random.default_rng(seed)
    n = operator.shape[0]
    raw = rng.standard_normal((n, n)) + 1j * rng.standard_normal((n, n))
    pert = 0.5 * (raw + raw.conj().T)
    norm_p = float(np.linalg.norm(pert, ord=2))
    if norm_p > 0:
        pert = pert * (epsilon / norm_p)

    lam_base = np.sort(np.linalg.eigvalsh(operator))
    lam_pert = np.sort(np.linalg.eigvalsh(operator + pert))
    max_shift = float(np.max(np.abs(lam_pert - lam_base)))
    weyl_bound = float(np.linalg.norm(pert, ord=2))
    return PerturbationResult(
        epsilon=epsilon,
        max_eigenvalue_shift=max_shift,
        weyl_upper_bound=weyl_bound,
        bound_satisfied=max_shift <= weyl_bound + 1e-12,
    )
