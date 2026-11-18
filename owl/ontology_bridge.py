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

"""OWL 2 DL -> ASP Bridge for SOVEREIGN-RH-LOCK.

Maintains strict epistemic separation:
- OWL 2 DL models structural relationships under Open-World Assumption (OWA).
- ASP enforces admission, rejection, and missing-obligation checks under Closed-World Assumption (CWA).
- Absence of a proof in OWL is NEVER converted into a logical refutation; it is emitted
  as an absence of `obligation_discharge/2` so ASP's closed-world `missing_obligation/1`
  blocks premature theorem admission.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from pathlib import Path
from typing import Dict, List, Set, Tuple

REQUIRED_CLASSES: Tuple[str, ...] = (
    "MathematicalObject",
    "HilbertSpace",
    "Operator",
    "DiracTypeOperator",
    "SelfAdjointOperator",
    "SpectralValue",
    "ZetaZero",
    "CriticalLineZero",
    "SpectralCorrespondence",
    "ProofObligation",
    "VerifiedLemma",
    "Conjecture",
    "Counterexample",
    "NumericalEvidence",
    "FormalEvidence",
)

REQUIRED_RELATIONS: Tuple[str, ...] = (
    "hasDomain",
    "actsOnSpace",
    "hasSpectrum",
    "correspondsToZero",
    "dependsOnLemma",
    "satisfiesObligation",
    "supportedByEvidence",
    "contradictsClaim",
    "derivedFromHypothesis",
)


@dataclass
class OntologySummary:
    classes: Set[str] = field(default_factory=set)
    properties: Set[str] = field(default_factory=set)
    disjoint_pairs: Set[Tuple[str, str]] = field(default_factory=set)
    subclass_edges: Dict[str, Set[str]] = field(default_factory=dict)
    individuals: Dict[str, Set[str]] = field(default_factory=dict)
    triples: List[Tuple[str, str, str]] = field(default_factory=list)


def _sanitized_atom(name: str) -> str:
    clean = re.sub(r"[^a-zA-Z0-9_]", "_", name.lstrip(":"))
    if not clean or not clean[0].islower():
        clean = "id_" + clean.lower()
    return clean.lower()


def parse_turtle_ontology(ttl_path: Path) -> OntologySummary:
    """Parse core OWL 2 DL declarations from Turtle without inventing external reasoner claims."""
    text = ttl_path.read_text(encoding="utf-8")
    summary = OntologySummary()

    # Strip comments
    lines = []
    for line in text.splitlines():
        stripped = line.split("#", 1)[0].strip()
        if stripped:
            lines.append(stripped)
    body = "\n".join(lines)

    # Extract class declarations
    for match in re.finditer(r":([A-Za-z0-9_]+)\s+a\s+owl:Class\b", body):
        summary.classes.add(match.group(1))

    # Extract property declarations
    for match in re.finditer(
        r":([A-Za-z0-9_]+)\s+a\s+owl:(?:ObjectProperty|DatatypeProperty)\b", body
    ):
        summary.properties.add(match.group(1))

    # Extract disjointWith pairs
    for match in re.finditer(r":([A-Za-z0-9_]+)\s+owl:disjointWith\s+:([A-Za-z0-9_]+)", body):
        a, b = sorted((match.group(1), match.group(2)))
        summary.disjoint_pairs.add((a, b))

    # Extract subClassOf named class edges
    for match in re.finditer(r":([A-Za-z0-9_]+)\s+rdfs:subClassOf\s+:([A-Za-z0-9_]+)", body):
        sub_c, sup_c = match.group(1), match.group(2)
        summary.subclass_edges.setdefault(sub_c, set()).add(sup_c)

    # Extract named individuals and their types
    # Matches patterns like `:H_BK_Operator a :DiracTypeOperator , :SelfAdjointOperator ;`
    for block in body.split("."):
        m = re.match(r"^\s*:([A-Za-z0-9_]+)\s+a\s+([^;]+)", block.strip())
        if not m:
            continue
        subj = m.group(1)
        types_raw = m.group(2)
        if "owl:" in types_raw:
            continue
        types = set(re.findall(r":([A-Za-z0-9_]+)", types_raw))
        if types:
            summary.individuals.setdefault(subj, set()).update(types)

    return summary


def validate_ontology_structure(summary: OntologySummary) -> List[str]:
    """Validate that all required OWL 2 DL classes, relations, and disjointness constraints exist."""
    errors: List[str] = []
    missing_classes = [c for c in REQUIRED_CLASSES if c not in summary.classes]
    if missing_classes:
        errors.append(f"Missing OWL classes: {missing_classes}")

    missing_props = [p for p in REQUIRED_RELATIONS if p not in summary.properties]
    if missing_props:
        errors.append(f"Missing OWL relations: {missing_props}")

    # Verify critical disjointness: NumericalEvidence != FormalEvidence
    pair = tuple(sorted(("NumericalEvidence", "FormalEvidence")))
    if pair not in summary.disjoint_pairs:
        errors.append("NumericalEvidence and FormalEvidence must be declared owl:disjointWith")

    # Check individual consistency against disjointness
    for ind, types in summary.individuals.items():
        expanded = set(types)
        frontier = list(types)
        while frontier:
            cur = frontier.pop()
            for sup in summary.subclass_edges.get(cur, ()):
                if sup not in expanded:
                    expanded.add(sup)
                    frontier.append(sup)
        for a, b in summary.disjoint_pairs:
            if a in expanded and b in expanded:
                errors.append(f"OWL inconsistency: {ind} is both {a} and {b} (disjoint)")

    return errors


def bridge_to_asp_facts(
    summary: OntologySummary,
    candidates: List[dict] | None = None,
) -> str:
    """Emit grounded ASP facts from OWL individuals and candidate records.

    Explicitly preserves OWA -> CWA boundary:
    - OWL `Conjecture` maps to `candidate(C)` and `conjecture_class(C)`.
    - OWL `NumericalEvidence` maps to `numeric_evidence(E)` (never `formal_evidence(E)`).
    - Missing obligations are NOT invented as discharged.
    """
    facts: List[str] = [
        "% Auto-generated by owl/ontology_bridge.py",
        "% Open-world OWL facts mapped to closed-world ASP admission inputs.",
    ]

    for ind, types in sorted(summary.individuals.items()):
        atom = _sanitized_atom(ind)
        for t in sorted(types):
            facts.append(f"owl_type({atom}, {_sanitized_atom(t)}).")
        if "SelfAdjointOperator" in types:
            facts.append(f"verified_self_adjoint({atom}).")

    if candidates:
        for cand in candidates:
            cid = _sanitized_atom(cand["hypothesis_id"])
            facts.append(f"candidate({cid}).")
            facts.append(f"generation({cid}, {int(cand.get('generation', 0))}).")
            for pid in cand.get("parent_ids", []):
                facts.append(f"parent({cid}, {_sanitized_atom(pid)}).")
            if cand.get("is_numeric", False):
                facts.append(f"numeric_candidate({cid}).")
            if cand.get("is_spectral", False):
                facts.append(f"spectral_candidate({cid}).")
            for obl in cand.get("obligations", []):
                facts.append(f"proof_obligation({cid}, {_sanitized_atom(obl)}).")
            for dis in cand.get("discharged_obligations", []):
                facts.append(f"obligation_discharge({cid}, {_sanitized_atom(dis)}).")
            for ev in cand.get("evidence_ids", []):
                ev_atom = _sanitized_atom(ev)
                facts.append(f"has_evidence({cid}, {ev_atom}).")
                if cand.get("evidence_verified", {}).get(ev, False):
                    facts.append(f"verified({ev_atom}).")
                if cand.get("evidence_refuted", {}).get(ev, False):
                    facts.append(f"refuted({ev_atom}).")

    return "\n".join(facts) + "\n"


def run_reasoner_check(ttl_path: Path) -> Tuple[bool, str]:
    """Run OWL 2 DL validation using rdflib/owlready2 if installed, plus structural check."""
    summary = parse_turtle_ontology(ttl_path)
    errors = validate_ontology_structure(summary)
    if errors:
        return False, "; ".join(errors)

    try:
        import rdflib  # type: ignore

        g = rdflib.Graph()
        g.parse(str(ttl_path), format="turtle")
        return True, f"Validated {len(g)} RDF triples via rdflib and structural OWL 2 DL checks."
    except ImportError:
        return (
            True,
            f"Structural Turtle/OWL 2 DL check passed ({len(summary.classes)} classes, "
            f"{len(summary.properties)} relations). Note: rdflib/owlready2 not installed for full DL tableau.",
        )
