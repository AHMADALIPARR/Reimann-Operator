% SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-SnapKitty-Opaque-1.0
% Copyright (C) 2026 Ahmad Ali Parr / SnapKitty Research Lab
%
% DSPy signature specs for the SOVEREIGN-RH-LOCK conjecture and proof-audit engine
% (SWI-Prolog port of SIGNATURE_SPECS in dspy/signatures.py).
%
%   signature_spec(Name, Inputs, Outputs, Role)
%
% Usage: swipl dspy/signatures.pl            prints the table as JSON, in declaration order
%        swipl dspy/signatures.pl roles      prints Name<TAB>Role per line

:- module(signatures, [signature_spec/4]).
:- initialization(main, main).

signature_spec('GenerateSpectralHypothesis',
               [parent_hypotheses, open_obligations, entropy_summary],
               [mathematical_statement, assumptions, claimed_derivation, target_obligations],
               exploratory_high_temp).
signature_spec('ConstructAdelicOperator',
               [hilbert_space_spec, scaling_action, cutoff_parameter],
               [operator_definition, dense_domain, symmetry_argument],
               exploratory_high_temp).
signature_spec('AnalyzeSelfAdjointness',
               [operator_definition, dense_domain],
               [deficiency_indices, extension_family, self_adjoint_verdict],
               deterministic_verdict).
signature_spec('GenerateZetaZeroCandidate',
               [spectral_interval, operator_eigenvalues],
               [candidate_real, candidate_imag, correspondence_rationale],
               exploratory_high_temp).
signature_spec('DeriveEntropyFeatures',
               [density_spectrum, hypothesis_distribution],
               [von_neumann_note, shannon_note, priority_features],
               deterministic_verdict).
signature_spec('ProposeSpectralPruningRule',
               [residual_threshold, entropy_threshold, generation],
               [pruning_predicate, provenance_preservation_note],
               exploratory_high_temp).
signature_spec('ConstructASPConstraint',
               [obligation_id, domain_rule, rejection_condition],
               [clingo_rule, integrity_constraint],
               deterministic_verdict).
signature_spec('ConstructOWLClassification',
               [entity_name, mathematical_role, evidence_type],
               [owl_classes, object_properties, open_world_note],
               deterministic_verdict).
signature_spec('SearchForCounterexample',
               [mathematical_statement, assumptions, spectral_evidence],
               [counterexample_found, counterexample_witness, refutation_reason],
               deterministic_verdict).
signature_spec('AuditMathematicalProof',
               [mathematical_statement, claimed_derivation, discharged_obligations],
               [missing_obligations, circularity_detected, formal_verdict],
               deterministic_verdict).

json_atom(A) :- format('"~w"', [A]).
json_list(L) :- write('['), json_items(L), write(']').
json_items([]).
json_items([X]) :- !, json_atom(X).
json_items([X|T]) :- json_atom(X), write(', '), json_items(T).

print_spec(first, N, I, O, R) :- print_spec_body(N, I, O, R).
print_spec(next, N, I, O, R) :- write(', '), print_spec_body(N, I, O, R).
print_spec_body(N, I, O, R) :-
    json_atom(N), write(': {"name": '), json_atom(N),
    write(', "inputs": '), json_list(I),
    write(', "outputs": '), json_list(O),
    write(', "role": '), json_atom(R), write('}').

main([roles]) :- !, forall(signature_spec(N, _, _, R), format('~w\t~w~n', [N, R])).
main(_) :-
    findall(s(N, I, O, R), signature_spec(N, I, O, R), [s(N0, I0, O0, R0)|Rest]),
    write('{'), print_spec(first, N0, I0, O0, R0),
    forall(member(s(N, I, O, R), Rest), print_spec(next, N, I, O, R)),
    write('}'), nl.
