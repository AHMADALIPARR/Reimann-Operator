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

% spectral_constraints.lp — Domain, self-adjointness, and spectral compatibility rules
% Clingo-compatible Answer Set Programming (ASP)

% Core predicates
#defined candidate/1.
#defined operator_for/2.
#defined domain_defined/1.
#defined symmetric_operator/1.
#defined verified_self_adjoint/1.
#defined spectral_candidate/1.
#defined numeric_candidate/1.
#defined correspondence_claimed/1.
#defined completeness_proved/1.
#defined multiplicity_accounted/1.
#defined inconsistent_assumption/1.
#defined spectral_domain_compatible/2.

% Spectral-domain compatibility requires an explicit Hilbert space & dense domain
spectral_domain_compatible(C, Op) :-
    candidate(C),
    operator_for(C, Op),
    domain_defined(Op).

% Self-adjointness prerequisite: symmetry alone is insufficient
self_adjoint_ready(Op) :-
    domain_defined(Op),
    symmetric_operator(Op),
    verified_self_adjoint(Op).

% Reject candidates claiming self-adjoint spectral correspondence without verified self-adjointness
rejected(C) :-
    candidate(C),
    spectral_candidate(C),
    operator_for(C, Op),
    not self_adjoint_ready(Op).

% Reject candidates with incompatible or missing operator domain
rejected(C) :-
    candidate(C),
    operator_for(C, Op),
    not spectral_domain_compatible(C, Op).

% Reject candidates carrying inconsistent assumptions
rejected(C) :-
    candidate(C),
    inconsistent_assumption(C).

% Exact correspondence prerequisites (Gate 9)
correspondence_ready(C) :-
    candidate(C),
    operator_for(C, Op),
    self_adjoint_ready(Op),
    completeness_proved(C),
    multiplicity_accounted(C).

rejected(C) :-
    candidate(C),
    correspondence_claimed(C),
    not correspondence_ready(C).
