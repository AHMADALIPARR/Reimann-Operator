% SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-SnapKitty-Opaque-1.0
% Copyright (C) 2026 Ahmad Ali Parr / SnapKitty Research Lab
%
% ontology_graph.pl: SVG class graph of an OWL ontology in Turtle.
% Named owl:Class nodes are layered by rdfs:subClassOf depth (solid arrows);
% object properties whose domain and range are named classes are drawn as
% dashed arcs labelled with the property name.
% usage: swipl docs/plots/ontology_graph.pl owl/rh_ontology.ttl > docs/images/ontology_classes.svg

:- use_module(library(semweb/rdf_db)).
:- use_module(library(semweb/turtle)).
:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(library(pairs)).
:- initialization(main, main).

main :-
    current_prolog_flag(argv, [File|_]),
    rdf_load(File, [format(turtle)]),
    findall(C, (rdf(C, rdf:type, owl:'Class'), \+ rdf_is_bnode(C)), Cs0),
    sort(Cs0, Cs),
    maplist(node_depth, Cs, Ds),
    pairs_keys_values(DC, Ds, Cs),
    max_list(Ds, MaxD),
    numlist(0, MaxD, Levels),
    foldl(place_level(DC), Levels, [], Pos),
    findall(e(S,P), (member(S,Cs), rdf(S, rdfs:subClassOf, P), \+ rdf_is_bnode(P)), SubEdges),
    findall(p(N,D,R), ( rdf(Pr, rdf:type, owl:'ObjectProperty'),
                        rdf(Pr, rdfs:domain, D), \+ rdf_is_bnode(D),
                        rdf(Pr, rdfs:range, R), \+ rdf_is_bnode(R),
                        local(Pr, N) ), PropEdges0),
    sort(PropEdges0, PropEdges),
    length(Cs, NC), length(SubEdges, NS), length(PropEdges, NP),
    width(Wd), height(Ht),
    format('<svg xmlns="http://www.w3.org/2000/svg" width="~w" height="~w" viewBox="0 0 ~w ~w" font-family="sans-serif" font-size="11">~n', [Wd,Ht,Wd,Ht]),
    format('<defs><marker id="a" viewBox="0 0 8 8" refX="7" refY="4" markerWidth="7" markerHeight="7" orient="auto"><path d="M0 0L8 4L0 8z" fill="#1f4e9a"/></marker>', []),
    format('<marker id="b" viewBox="0 0 8 8" refX="7" refY="4" markerWidth="6" markerHeight="6" orient="auto"><path d="M0 0L8 4L0 8z" fill="#999"/></marker></defs>~n', []),
    format('<rect width="~w" height="~w" fill="#fff"/>~n', [Wd,Ht]),
    Xt is Wd / 2,
    format('<text x="~w" y="18" text-anchor="middle" font-size="13">~w: ~w classes, ~w subClassOf edges, ~w object properties between named classes</text>~n',
           [Xt, File, NC, NS, NP]),
    forall(member(e(S,P), SubEdges), sub_edge(Pos, S, P)),
    forall(member(p(N,D,R), PropEdges), prop_edge(Pos, N, D, R)),
    forall(member(C-(X-Y), Pos), box(C, X, Y)),
    Ly is Ht - 14, Ll is Ly - 4,
    format('<line x1="20" x2="44" y1="~w" y2="~w" stroke="#1f4e9a" marker-end="url(#a)"/><text x="50" y="~w">rdfs:subClassOf</text>', [Ll,Ll,Ly]),
    format('<line x1="170" x2="194" y1="~w" y2="~w" stroke="#999" stroke-dasharray="4 3" marker-end="url(#b)"/><text x="200" y="~w">owl:ObjectProperty (domain → range)</text>~n', [Ll,Ll,Ly]),
    format('</svg>~n', []).

width(960).
height(380).
level_y(L, Y) :- Y is 95 + L * 110.

local(IRI, Name) :- ( sub_atom(IRI, B, 1, _, '#') -> B1 is B+1, sub_atom(IRI, B1, _, 0, Name) ; Name = IRI ).
box_w(C, W) :- local(C, N), atom_length(N, L), W is L * 6.6 + 18.

node_depth(C, D) :-
    findall(P, (rdf(C, rdfs:subClassOf, P), \+ rdf_is_bnode(P)), Ps),
    ( Ps == [] -> D = 0 ; maplist(node_depth, Ps, PDs), max_list(PDs, M), D is M + 1 ).

place_level(DC, L, Acc, Out) :-
    findall(C, member(L-C, DC), Cs0),
    % order a level by the mean x of its already placed parents, then by name
    map_list_to_pairs(parent_x(Acc), Cs0, Keyed), keysort(Keyed, Sorted), pairs_values(Sorted, Cs),
    maplist(box_w, Cs, Ws), sum_list(Ws, SW), length(Cs, N),
    width(Wd), Gap = 22, Total is SW + Gap * (N - 1), X0 is (Wd - Total) / 2,
    level_y(L, Y),
    foldl(place_one(Y, Gap), Cs, X0-Acc, _-Out).
parent_x(Acc, C, K-C) :-
    findall(X, (rdf(C, rdfs:subClassOf, P), memberchk(P-(X-_), Acc)), Xs),
    ( Xs == [] -> K = 0 ; sum_list(Xs, S), length(Xs, N), K is S / N ).
place_one(Y, Gap, C, X-Acc, X1-[C-(Xc-Y)|Acc]) :-
    box_w(C, W), Xc is X + W / 2, X1 is X + W + Gap.

box(C, X, Y) :-
    local(C, N), box_w(C, W), X0 is X - W/2, Y0 is Y - 12,
    format('<rect x="~1f" y="~w" width="~1f" height="24" rx="5" fill="#eef3fb" stroke="#1f4e9a"/><text x="~1f" y="~w" text-anchor="middle">~w</text>~n',
           [X0, Y0, W, X, Y+4, N]).

sub_edge(Pos, S, P) :-
    memberchk(S-(X1-Y1), Pos), memberchk(P-(X2-Y2), Pos),
    Ya is Y1 - 12, Yb is Y2 + 13,
    format('<line x1="~1f" y1="~w" x2="~1f" y2="~w" stroke="#1f4e9a" marker-end="url(#a)"/>~n', [X1, Ya, X2, Yb]).

prop_edge(Pos, N, D, R) :-
    memberchk(D-(X1-Y1), Pos), memberchk(R-(X2-Y2), Pos),
    (   D == R
    ->  Xs is X1 + 20, Ys is Y1 - 12, Xe is X1 + 34, Ye is Y1 - 12,
        Cx1 is X1 + 10, Cx2 is X1 + 50, Cy is Y1 - 48, Ty is Y1 - 44,
        format('<path d="M~1f ~w C~1f ~w ~1f ~w ~1f ~w" fill="none" stroke="#999" stroke-dasharray="4 3" marker-end="url(#b)"/>', [Xs,Ys,Cx1,Cy,Cx2,Cy,Xe,Ye]),
        Tx is X1 + 30, format('<text x="~1f" y="~w" text-anchor="middle" font-size="9" fill="#666">~w</text>~n', [Tx, Ty, N])
    ;   Y1 =:= Y2
    ->  ( level_y(0, Y1) -> Sgn = -1 ; Sgn = 1 ),
        H is Sgn * (14 + min(abs(X2 - X1) * 0.05, 18)),
        Ys is Y1 + Sgn * 12, Cy is Ys + 2 * H, Ty is Ys + 0.84 * H + Sgn * 4 + (Sgn + 1) * 3,
        Cx is (X1 + X2) / 2, Tx is X1 + 0.7 * (X2 - X1),
        format('<path d="M~1f ~w Q~1f ~1f ~1f ~w" fill="none" stroke="#999" stroke-dasharray="4 3" marker-end="url(#b)"/>', [X1,Ys,Cx,Cy,X2,Ys]),
        format('<text x="~1f" y="~1f" text-anchor="middle" font-size="9" fill="#666">~w</text>~n', [Tx, Ty, N])
    ;   ( Y1 > Y2 -> Ya is Y1 - 12, Yb is Y2 + 13 ; Ya is Y1 + 13, Yb is Y2 - 12 ),
        Xa is X1 + 18, Xb is X2 + 18, Tx is (Xa + Xb) / 2 + 6, Ty is (Ya + Yb) / 2,
        format('<line x1="~1f" y1="~w" x2="~1f" y2="~w" stroke="#999" stroke-dasharray="4 3" marker-end="url(#b)"/>', [Xa,Ya,Xb,Yb]),
        format('<text x="~1f" y="~1f" font-size="9" fill="#666">~w</text>~n', [Tx, Ty, N])
    ).
