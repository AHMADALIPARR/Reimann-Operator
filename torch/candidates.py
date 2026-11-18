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

"""Candidate ranking, lineage tracking, and Klong 64-bit SoA binary interchange."""

from __future__ import annotations

import hashlib
import json
import struct
from dataclasses import dataclass, field
from typing import Dict, List, Sequence

import numpy as np

KLONG_MAGIC = b"SRHLK64\x00"
KLONG_VERSION = 1
KLONG_N_COLS = 9


@dataclass
class NumericCandidate:
    candidate_id: int
    parent_id: int
    generation: int
    zero_real: float
    zero_imag: float
    eigenvalue_real: float
    entropy: float
    residual: float
    status: int = 1  # 1=active, 2=pruned, -1=invalid
    info_gain: float = 0.0
    novelty: float = 0.0
    obligation_progress: float = 0.0

    def priority_score(
        self, w1: float = 1.0, w2: float = 0.5, w3: float = 2.0, w4: float = 1.5
    ) -> float:
        """Heuristic search objective J(C) = w1*I + w2*N + w3*D - w4*R.
        Search heuristic only; never a mathematical invariant.
        """
        vals = (self.entropy, self.novelty, self.obligation_progress, self.residual)
        if not all(np.isfinite(vals)):
            return float("-inf")
        return w1 * self.entropy + w2 * self.novelty + w3 * self.obligation_progress - w4 * self.residual


@dataclass
class ProvenanceLedger:
    """Append-only SHA-256 chained provenance ledger.
    Numerically pruned candidates remain recorded with status=2.
    """

    records: List[Dict] = field(default_factory=list)

    def record(self, candidate: NumericCandidate, note: str = "") -> str:
        prev_hash = self.records[-1]["entry_hash"] if self.records else "0" * 64
        payload = {
            "prev_hash": prev_hash,
            "candidate_id": candidate.candidate_id,
            "parent_id": candidate.parent_id,
            "generation": candidate.generation,
            "zero_real": candidate.zero_real,
            "zero_imag": candidate.zero_imag,
            "eigenvalue_real": candidate.eigenvalue_real,
            "entropy": candidate.entropy,
            "residual": candidate.residual,
            "status": candidate.status,
            "note": note,
        }
        canonical = json.dumps(payload, sort_keys=True, separators=(",", ":")).encode("utf-8")
        entry_hash = hashlib.sha256(canonical).hexdigest()
        payload["entry_hash"] = entry_hash
        self.records.append(payload)
        return entry_hash

    def verify_chain(self) -> bool:
        prev = "0" * 64
        for entry in self.records:
            if entry["prev_hash"] != prev:
                return False
            check = {k: v for k, v in entry.items() if k != "entry_hash"}
            canonical = json.dumps(check, sort_keys=True, separators=(",", ":")).encode("utf-8")
            if hashlib.sha256(canonical).hexdigest() != entry["entry_hash"]:
                return False
            prev = entry["entry_hash"]
        return True


def rank_candidates(candidates: Sequence[NumericCandidate]) -> List[NumericCandidate]:
    """Rank candidates deterministically by heuristic J(C), breaking ties by candidate_id."""
    return sorted(
        candidates,
        key=lambda c: (-c.priority_score(), c.candidate_id),
    )


def pack_soa_binary(candidates: Sequence[NumericCandidate]) -> bytes:
    """Serialize candidates into Klong-compatible flat 64-bit SoA binary layout."""
    n = len(candidates)
    header = struct.pack("<8sqqq", KLONG_MAGIC, KLONG_VERSION, n, KLONG_N_COLS)
    if n == 0:
        return header

    c_id = np.array([c.candidate_id for c in candidates], dtype="<i8")
    p_id = np.array([c.parent_id for c in candidates], dtype="<i8")
    gen = np.array([c.generation for c in candidates], dtype="<i8")
    zr = np.array([c.zero_real for c in candidates], dtype="<f8")
    zi = np.array([c.zero_imag for c in candidates], dtype="<f8")
    ev = np.array([c.eigenvalue_real for c in candidates], dtype="<f8")
    ent = np.array([c.entropy for c in candidates], dtype="<f8")
    res = np.array([c.residual for c in candidates], dtype="<f8")
    st = np.array([c.status for c in candidates], dtype="<i8")

    return b"".join(
        [
            header,
            c_id.tobytes(),
            p_id.tobytes(),
            gen.tobytes(),
            zr.tobytes(),
            zi.tobytes(),
            ev.tobytes(),
            ent.tobytes(),
            res.tobytes(),
            st.tobytes(),
        ]
    )


def unpack_soa_binary(blob: bytes) -> List[NumericCandidate]:
    """Deserialize Klong-compatible flat 64-bit SoA binary layout with strict ABI checks."""
    if len(blob) < 32:
        raise ValueError(f"Buffer too small for 32-byte header: {len(blob)} bytes")
    magic, version, n, n_cols = struct.unpack("<8sqqq", blob[:32])
    if magic != KLONG_MAGIC:
        raise ValueError(f"Invalid magic header: {magic!r}")
    if version != KLONG_VERSION:
        raise ValueError(f"Unsupported contract version: {version}")
    if n_cols != KLONG_N_COLS:
        raise ValueError(f"Unexpected column count: {n_cols}")
    expected_len = 32 + n * n_cols * 8
    if len(blob) != expected_len:
        raise ValueError(f"Length mismatch: expected {expected_len}, got {len(blob)}")
    if n == 0:
        return []

    offset = 32
    stride = n * 8

    def _slice(dtype: str) -> np.ndarray:
        nonlocal offset
        arr = np.frombuffer(blob, dtype=dtype, count=n, offset=offset)
        offset += stride
        return arr

    c_id = _slice("<i8")
    p_id = _slice("<i8")
    gen = _slice("<i8")
    zr = _slice("<f8")
    zi = _slice("<f8")
    ev = _slice("<f8")
    ent = _slice("<f8")
    res = _slice("<f8")
    st = _slice("<i8")

    return [
        NumericCandidate(
            candidate_id=int(c_id[i]),
            parent_id=int(p_id[i]),
            generation=int(gen[i]),
            zero_real=float(zr[i]),
            zero_imag=float(zi[i]),
            eigenvalue_real=float(ev[i]),
            entropy=float(ent[i]),
            residual=float(res[i]),
            status=int(st[i]),
        )
        for i in range(n)
    ]
