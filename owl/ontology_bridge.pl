% SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-SnapKitty-Opaque-1.0
% Copyright (C) 2026 Ahmad Ali Parr / SnapKitty Research Lab
%
% OWL 2 DL -> ASP bridge for SOVEREIGN-RH-LOCK (SWI-Prolog port of owl/ontology_bridge.py).
%
% OWL (open world) describes structure; ASP (closed world) admits or rejects. A proof that
% is absent in OWL is never turned into a refutation: it shows up as a missing
% obligation_discharge/2 fact, so ASP's missing_obligation/1 blocks admission.
%
% Usage:
%   swipl owl/ontology_bridge.pl summary  FILE.ttl
%   swipl owl/ontology_bridge.pl validate FILE.ttl
%   swipl owl/ontology_bridge.pl facts    FILE.ttl [CANDIDATES.json]
%   swipl owl/ontology_bridge.pl check    FILE.ttl [--structural]
%
% summary/validate/facts read the Turtle with the same declaration patterns as the Python.
% check also loads the file with library(semweb/turtle) and reports the RDF triple count.

:- module(ontology_bridge,
          [ parse_turtle_ontology/2, validate_ontology_structure/2,
            bridge_to_asp_facts/3, run_reasoner_check/3, sanitized_atom/2 ]).

:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(library(pairs)).
:- if(exists_source(library(json))).
:- use_module(library(json)).
:- else.
:- use_module(library(http/json)).
:- endif.
:- use_module(library(semweb/rdf_db)).
:- use_module(library(semweb/turtle)).

:- initialization(main, main).

required_class('MathematicalObject').
required_class('HilbertSpace').
required_class('Operator').
required_class('DiracTypeOperator').
required_class('SelfAdjointOperator').
required_class('SpectralValue').
required_class('ZetaZero').
required_class('CriticalLineZero').
required_class('SpectralCorrespondence').
required_class('ProofObligation').
required_class('VerifiedLemma').
required_class('Conjecture').
required_class('Counterexample').
required_class('NumericalEvidence').
required_class('FormalEvidence').

required_relation(hasDomain).
required_relation(actsOnSpace).
required_relation(hasSpectrum).
required_relation(correspondsToZero).
required_relation(dependsOnLemma).
required_relation(satisfiesObligation).
required_relation(supportedByEvidence).
required_relation(contradictsClaim).
required_relation(derivedFromHypothesis).

%% summary(Classes, Properties, DisjointPairs, SubclassEdges, Individuals)
%   Classes, Properties: sorted atom sets.  DisjointPairs: sorted A-B with A @< B.
%   SubclassEdges: sorted Sub-SortedSupers.  Individuals: Subject-SortedTypes in first-seen order.

% ------------------------------------------------------------------ text
py_space(C) :- memberchk(C, [0' , 0'\t, 0'\n, 0'\r, 0'\v, 0'\f, 0x1c, 0x1d, 0x1e, 0x1f, 0x85, 0xa0]).
id_char(C) :- code_type(C, csym), C < 128.

strip_codes(Cs, S) :-
    drop_space(Cs, A), reverse(A, RA), drop_space(RA, RB), reverse(RB, S).
drop_space([C|T], R) :- py_space(C), !, drop_space(T, R).
drop_space(L, L).

%  Comment stripping exactly as the Python: cut each line at its first '#', strip, drop empties.
body_codes(Text, Body) :-
    split_string(Text, "\n", "", Lines0),
    fix_crlf(Lines0, Lines),
    foldl(keep_line, Lines, [], RevKept),
    reverse(RevKept, Kept),
    atomic_list_concat(Kept, '\n', BodyA),
    atom_codes(BodyA, Body).
fix_crlf(Ls, Ls).
keep_line(L, Acc, Acc1) :-
    string_codes(L, Cs0),
    ( append(Before, [0'#|_], Cs0) -> first_hash(Cs0, Before1) ; Before1 = Cs0 ),
    ignore(Before = Before),
    strip_codes(Before1, S),
    ( S == [] -> Acc1 = Acc ; atom_codes(A, S), Acc1 = [A|Acc] ).
first_hash(Cs, Before) :- append(Before, [0'#|_], Cs), \+ memberchk(0'#, Before), !.

% ----------------------------------------------------------- matchers
ident([C|Cs]) --> [C], { id_char(C) }, ident_rest(Cs).
ident_rest([C|Cs]) --> [C], { id_char(C) }, !, ident_rest(Cs).
ident_rest([]) --> [].
ws1 --> [C], { py_space(C) }, ws0.
ws0 --> [C], { py_space(C) }, !, ws0.
ws0 --> [].
lit([]) --> [].
lit([C|Cs]) --> [C], lit(Cs).
word_boundary, [C] --> [C], !, { \+ id_char(C) }.
word_boundary --> [].

pat(class(Id)) -->
    ":", ident(I), ws1, "a", ws1, lit(`owl:Class`), word_boundary, { atom_codes(Id, I) }.
pat(prop(Id)) -->
    ":", ident(I), ws1, "a", ws1, lit(`owl:`),
    ( lit(`ObjectProperty`) ; lit(`DatatypeProperty`) ), word_boundary, { atom_codes(Id, I) }.
pat(disjoint(A, B)) -->
    ":", ident(I), ws1, lit(`owl:disjointWith`), ws1, ":", ident(J),
    { atom_codes(A, I), atom_codes(B, J) }.
pat(subclass(A, B)) -->
    ":", ident(I), ws1, lit(`rdfs:subClassOf`), ws1, ":", ident(J),
    { atom_codes(A, I), atom_codes(B, J) }.

%  finditer: non-overlapping, leftmost-first.
find_all(_, [], []) :- !.
find_all(Kind, Codes, Out) :-
    copy_term(Kind, K),
    (   phrase(pat(K), Codes, Rest)
    ->  Out = [K|More], find_all(Kind, Rest, More)
    ;   Codes = [_|T], find_all(Kind, T, Out)
    ).

colon_idents([], []).
colon_idents([0':|T], [Id|Ids]) :-
    phrase(ident(I), T, Rest), !, atom_codes(Id, I), colon_idents(Rest, Ids).
colon_idents([_|T], Ids) :- colon_idents(T, Ids).

% ------------------------------------------------------------- parsing
parse_turtle_ontology(File, summary(Classes, Props, Pairs, Edges, Inds)) :-
    read_file_to_string(File, Text, [encoding(utf8)]),
    body_codes(Text, Body),
    find_all(class(_), Body, Cl), findall(C, member(class(C), Cl), Cs), sort(Cs, Classes),
    find_all(prop(_), Body, Pr), findall(P, member(prop(P), Pr), Ps), sort(Ps, Props),
    find_all(disjoint(_, _), Body, Dj),
    findall(X-Y, ( member(disjoint(A, B), Dj), msort([A, B], [X, Y]) ), Ds), sort(Ds, Pairs),
    find_all(subclass(_, _), Body, Sb),
    findall(S-U, member(subclass(S, U), Sb), SUs),
    edges(SUs, Edges),
    split_on_dot(Body, Blocks),
    foldl(individual_block, Blocks, [], RevInds),
    reverse(RevInds, Inds0),
    maplist([N-Ts, N-STs]>>sort(Ts, STs), Inds0, Inds).

edges(SUs, Edges) :-
    keysort(SUs, Sorted), group_pairs_by_key(Sorted, G),
    maplist([K-Vs, K-SVs]>>sort(Vs, SVs), G, Edges).

split_on_dot(Codes, Blocks) :-
    (   append(B, [0'.|Rest], Codes), \+ memberchk(0'., B)
    ->  Blocks = [B|More], split_on_dot(Rest, More)
    ;   Blocks = [Codes]
    ).

individual_block(Block0, Acc, Acc1) :-
    strip_codes(Block0, Block),
    (   phrase((":", ident(I), ws1, "a", ws1, nonsemi(Raw)), Block, _),
        Raw \== []
    ->  atom_codes(Subj, I),
        (   append(_, [0'o, 0'w, 0'l, 0':|_], Raw)
        ->  Acc1 = Acc
        ;   colon_idents(Raw, Types),
            (   Types == []
            ->  Acc1 = Acc
            ;   add_types(Subj, Types, Acc, Acc1)
            )
        )
    ;   Acc1 = Acc
    ).
nonsemi([C|Cs]) --> [C], { C \== 0'; }, !, nonsemi(Cs).
nonsemi([]) --> [].

add_types(S, Ts, Acc, Acc1) :-
    (   selectchk(S-Old, Acc, S-New, Acc1)
    ->  append(Old, Ts, New)
    ;   Acc1 = [S-Ts|Acc]
    ).

% ---------------------------------------------------------- validation
validate_ontology_structure(summary(Classes, Props, Pairs, Edges, Inds), Errors) :-
    findall(C, ( required_class(C), \+ memberchk(C, Classes) ), MC),
    findall(P, ( required_relation(P), \+ memberchk(P, Props) ), MP),
    ( MC == [] -> E1 = [] ; py_list(MC, L1), format(string(S1), "Missing OWL classes: ~w", [L1]), E1 = [S1] ),
    ( MP == [] -> E2 = [] ; py_list(MP, L2), format(string(S2), "Missing OWL relations: ~w", [L2]), E2 = [S2] ),
    (   memberchk('FormalEvidence'-'NumericalEvidence', Pairs)
    ->  E3 = []
    ;   E3 = ["NumericalEvidence and FormalEvidence must be declared owl:disjointWith"]
    ),
    findall(S,
            ( member(Ind-Types, Inds),
              closure(Types, Edges, Expanded),
              member(A-B, Pairs),
              memberchk(A, Expanded), memberchk(B, Expanded),
              format(string(S), "OWL inconsistency: ~w is both ~w and ~w (disjoint)", [Ind, A, B]) ),
            E4),
    append([E1, E2, E3, E4], Errors).

closure(Types, Edges, Expanded) :- closure_(Types, Edges, Types, Expanded).
closure_([], _, Seen, Seen).
closure_([T|Ts], Edges, Seen, Out) :-
    ( memberchk(T-Sups, Edges) -> true ; Sups = [] ),
    exclude([X]>>memberchk(X, Seen), Sups, New0), sort(New0, New),
    append(Seen, New, Seen1),
    append(Ts, New, Front),
    closure_(Front, Edges, Seen1, Out).

py_list(Atoms, Str) :-
    maplist([A, Q]>>format(string(Q), "'~w'", [A]), Atoms, Qs),
    atomic_list_concat(Qs, ', ', Inner),
    format(string(Str), "[~w]", [Inner]).

% --------------------------------------------------------------- ASP
sanitized_atom(Name, Atom) :-
    atom_codes(Name, Cs0),
    ( Cs0 = [0':|_] -> strip_colons(Cs0, Cs1) ; Cs1 = Cs0 ),
    maplist([C, D]>>( id_char(C) -> D = C ; D = 0'_ ), Cs1, Clean),
    (   Clean = [F|_], code_type(F, lower), F < 128
    ->  Out = Clean
    ;   append(`id_`, Clean, Out)
    ),
    atom_codes(A0, Out), downcase_atom(A0, Atom).
strip_colons([0':|T], R) :- !, strip_colons(T, R).
strip_colons(L, L).

bridge_to_asp_facts(summary(_, _, _, _, Inds), Candidates, Text) :-
    msort(Inds, SortedInds),
    findall(Line, individual_fact(SortedInds, Line), L1),
    findall(Line, ( member(C, Candidates), candidate_fact(C, Line) ), L2),
    append([["% Auto-generated by owl/ontology_bridge.py",
             "% Open-world OWL facts mapped to closed-world ASP admission inputs."], L1, L2], Lines),
    atomic_list_concat(Lines, '\n', T0),
    atom_concat(T0, '\n', Text).

individual_fact(Inds, Line) :-
    member(Ind-Types, Inds),
    sanitized_atom(Ind, A),
    (   member(T, Types), sanitized_atom(T, TA), format(string(Line), "owl_type(~w, ~w).", [A, TA])
    ;   memberchk('SelfAdjointOperator', Types), format(string(Line), "verified_self_adjoint(~w).", [A])
    ).

cget(C, K, D, V) :- ( get_dict(K, C, V0) -> V = V0 ; V = D ).
truthy(V) :- \+ memberchk(V, [false, 0, 0.0, "", [], null, @(false)]), \+ (is_dict(V), dict_pairs(V, _, [])).

candidate_fact(C, Line) :-
    get_dict(hypothesis_id, C, HId), atom_string(HA, HId), sanitized_atom(HA, Cid),
    cget(C, generation, 0, G0), ( G0 == true -> G = 1 ; G0 == false -> G = 0 ; G is truncate(G0) ),
    cget(C, parent_ids, [], Ps), cget(C, obligations, [], Os), cget(C, discharged_obligations, [], Ds),
    cget(C, evidence_ids, [], Es), cget(C, evidence_verified, _{}, EV), cget(C, evidence_refuted, _{}, ER),
    (   format(string(Line), "candidate(~w).", [Cid])
    ;   format(string(Line), "generation(~w, ~w).", [Cid, G])
    ;   member(P, Ps), san(P, PA), format(string(Line), "parent(~w, ~w).", [Cid, PA])
    ;   cget(C, is_numeric, false, N), truthy(N), format(string(Line), "numeric_candidate(~w).", [Cid])
    ;   cget(C, is_spectral, false, S), truthy(S), format(string(Line), "spectral_candidate(~w).", [Cid])
    ;   member(O, Os), san(O, OA), format(string(Line), "proof_obligation(~w, ~w).", [Cid, OA])
    ;   member(D, Ds), san(D, DA), format(string(Line), "obligation_discharge(~w, ~w).", [Cid, DA])
    ;   member(E, Es), san(E, EA), atom_string(EK, E),
        (   format(string(Line), "has_evidence(~w, ~w).", [Cid, EA])
        ;   cget(EV, EK, false, V), truthy(V), format(string(Line), "verified(~w).", [EA])
        ;   cget(ER, EK, false, R), truthy(R), format(string(Line), "refuted(~w).", [EA])
        )
    ).
san(S, A) :- atom_string(X, S), sanitized_atom(X, A).

% ------------------------------------------------------------ reasoner
run_reasoner_check(File, Mode, Result) :-
    parse_turtle_ontology(File, Sum),
    validate_ontology_structure(Sum, Errors),
    (   Errors \== []
    ->  atomic_list_concat(Errors, '; ', Msg), Result = false-Msg
    ;   Mode == structural
    ->  Sum = summary(Cl, Pr, _, _, _), length(Cl, NC), length(Pr, NP),
        format(string(Msg), "Structural Turtle/OWL 2 DL check passed (~w classes, ~w relations). Note: rdflib/owlready2 not installed for full DL tableau.", [NC, NP]),
        Result = true-Msg
    ;   rdf_reset_db,
        absolute_file_name(File, Abs),
        rdf_load(Abs, [format(turtle), graph(ontology), silent(true)]),
        aggregate_all(count, rdf(_, _, _, ontology), N),
        format(string(Msg), "Validated ~w RDF triples via rdflib and structural OWL 2 DL checks.", [N]),
        Result = true-Msg
    ).

% ---------------------------------------------------------------- JSON
json_str(S) :-
    string_codes(S, Cs),
    put_char('"'), maplist(json_code, Cs), put_char('"').
json_code(0'") :- !, write('\\"').
json_code(0'\\) :- !, write('\\\\').
json_code(0'\n) :- !, write('\\n').
json_code(C) :- C < 0x20, !, format("\\u~|~`0t~16r~4+", [C]).
json_code(C) :- C > 0x7e, !, format("\\u~|~`0t~16r~4+", [C]).
json_code(C) :- put_char(C).
json_atoms(As) :- put_char('['), json_seq(As), put_char(']').
json_seq([]).
json_seq([A]) :- !, json_str(A).
json_seq([A|T]) :- json_str(A), write(', '), json_seq(T).

print_summary(summary(Classes, Props, Pairs, Edges, Inds)) :-
    write('{"classes": '), json_atoms(Classes),
    write(', "properties": '), json_atoms(Props),
    write(', "disjoint_pairs": ['),
    print_items(Pairs, [A-B]>>json_atoms([A, B])),
    write('], "subclass_edges": {'),
    print_items(Edges, [K-V]>>(json_str(K), write(': '), json_atoms(V))),
    write('}, "individuals": {'),
    msort(Inds, SI),
    print_items(SI, [K-V]>>(json_str(K), write(': '), json_atoms(V))),
    write('}}'), nl.
print_items([], _).
print_items([X], G) :- !, call(G, X).
print_items([X|T], G) :- call(G, X), write(', '), print_items(T, G).

main(Argv) :-
    set_stream(user_output, encoding(utf8)),
    (   Argv = [summary, F] -> parse_turtle_ontology(F, S), print_summary(S)
    ;   Argv = [validate, F] -> parse_turtle_ontology(F, S), validate_ontology_structure(S, E),
        json_atoms(E), nl
    ;   Argv = [facts, F|Rest] ->
        parse_turtle_ontology(F, S),
        (   Rest = [CF]
        ->  setup_call_cleanup(open(CF, read, In, [encoding(utf8)]),
                               json_read_dict(In, Cands, [value_string_as(string), null(null), true(true), false(false)]),
                               close(In))
        ;   Cands = []
        ),
        bridge_to_asp_facts(S, Cands, T), write(T)
    ;   Argv = [check, F|Opt] ->
        ( Opt = ['--structural'] -> Mode = structural ; Mode = full ),
        run_reasoner_check(F, Mode, Ok-Msg),
        format("[~w, ", [Ok]), json_str(Msg), write(']'), nl
    ;   format(user_error, "usage: swipl owl/ontology_bridge.pl summary|validate|facts|check FILE.ttl [...]~n", []),
        halt(2)
    ).
