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

% recursive_pruning.lp — Recursive lineage constraints and counterexample propagation

#defined parent/2.
#defined generation/2.
#defined counterexample_found/1.
#defined rejected/1.
#defined candidate/1.

% Ancestor relation (non-circularity enforced)
ancestor(P, C) :- parent(C, P).
ancestor(A, C) :- ancestor(A, P), parent(C, P).

% Generation monotonicity: child generation must strictly exceed parent generation
:- parent(C, P), generation(C, GC), generation(P, GP), GC <= GP.

% Acyclic lineage
:- ancestor(X, X).

% Counterexample status propagation: if a parent is refuted by a counterexample,
% any child inheriting its core claim is tainted unless explicitly repaired.
lineage_tainted(C) :-
    parent(C, P),
    counterexample_found(P).

lineage_tainted(C) :-
    parent(C, P),
    lineage_tainted(P).

rejected(C) :-
    candidate(C),
    lineage_tainted(C).
