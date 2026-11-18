% Copyright (C) 2026 Ahmad Ali Parr / SnapKitty Research Lab
% 
% This program is free software: you can redistribute it and/or modify
% it under the terms of the GNU Affero General Public License as published by
% the Free Software Foundation, either version 3 of the License, or
% (at your option) any later version.
%
% This program is distributed in the hope that it will be useful,
% but WITHOUT ANY WARRANTY; without even the implied warranty of
% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
% GNU Affero General Public License for more details.
%
% You should have received a copy of the GNU Affero General Public License
% along with this program.  If not, see <https://www.gnu.org/licenses/>.

% proof_admission.lp — Closed-world admission, obligation discharge, and 5 epistemic states
% Never encode a numerical observation as a logical theorem.

#defined candidate/1.
#defined has_evidence/2.
#defined verified/1.
#defined refuted/1.
#defined formal_evidence/1.
#defined numeric_evidence/1.
#defined proof_obligation/2.
#defined obligation_discharge/2.
#defined numeric_candidate/1.
#defined spectral_candidate/1.
#defined depends_on_theorem/2.
#defined contradicts_theorem/2.
#defined counterexample_found/1.

% Required rejection rules
rejected(C) :-
    candidate(C),
    has_evidence(C, E),
    refuted(E).

rejected(C) :-
    candidate(C),
    counterexample_found(C).

missing_obligation(C) :-
    proof_obligation(C, O),
    not obligation_discharge(C, O).

rejected(C) :-
    candidate(C),
    missing_obligation(C).

% Contradictory theorem-dependency detection
rejected(C) :-
    candidate(C),
    depends_on_theorem(C, T1),
    depends_on_theorem(C, T2),
    contradicts_theorem(T1, T2).

% Non-circular proof-dependency constraints
depends_trans(X, Y) :- depends_on_theorem(X, Y).
depends_trans(X, Z) :- depends_trans(X, Y), depends_on_theorem(Y, Z).
:- depends_trans(X, X).

% Retention & formal admissibility
retained(C) :-
    candidate(C),
    not rejected(C).

formally_admissible(C) :-
    retained(C),
    has_evidence(C, E),
    formal_evidence(E),
    verified(E),
    not missing_obligation(C).

% Hard integrity constraints
:- retained(C), missing_obligation(C).
:- formally_admissible(C), not retained(C).
:- formally_admissible(C), has_evidence(C, E), numeric_evidence(E), not formal_evidence(E).

% Five mutually distinct epistemic states:
% 1. Candidate hypothesis
state_candidate(C) :- candidate(C).

% 2. Numerically supported hypothesis (not a theorem)
state_numerically_supported(C) :-
    candidate(C),
    numeric_candidate(C),
    has_evidence(C, E),
    numeric_evidence(E),
    not refuted(E),
    not counterexample_found(C).

% 3. Formally verified lemma
state_formally_verified_lemma(C) :-
    formally_admissible(C).

% 4. Refuted hypothesis
state_refuted(C) :-
    candidate(C),
    has_evidence(C, E),
    refuted(E).
state_refuted(C) :-
    candidate(C),
    counterexample_found(C).

% 5. Unresolved conjecture
state_unresolved_conjecture(C) :-
    candidate(C),
    not state_formally_verified_lemma(C),
    not state_refuted(C).
