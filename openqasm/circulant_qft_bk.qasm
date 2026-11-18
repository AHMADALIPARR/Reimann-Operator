OPENQASM 3.0;
include "stdgates.inc";

// SOVEREIGN-RH-LOCK: Circulant-QFT Block Encoding (n = 4 data qubits, N = 16)
// Implements U_A = (I x F_N^dagger) U_D (I x F_N)
// Target: periodic central-difference Berry-Keating stencil in u = ln(x) coordinates.
// Subnormalization bound: ||A_N||_2 <= alpha (finite-dimensional truncation only).

const float[64] PI = 3.141592653589793;
const float[64] THETA_0 = 0.25;
const float[64] THETA_1 = 0.50;
const float[64] THETA_2 = 1.00;
const float[64] THETA_3 = 2.00;

qubit[1] anc;
qubit[4] q;
bit[1] c_anc;
bit[4] c_q;

gate qft4 d0, d1, d2, d3 {
    h d3;
    cp(PI / 2.0) d2, d3;
    cp(PI / 4.0) d1, d3;
    cp(PI / 8.0) d0, d3;
    h d2;
    cp(PI / 2.0) d1, d2;
    cp(PI / 4.0) d0, d2;
    h d1;
    cp(PI / 2.0) d0, d1;
    h d0;
    swap d0, d3;
    swap d1, d2;
}

gate iqft4 d0, d1, d2, d3 {
    swap d0, d3;
    swap d1, d2;
    h d0;
    cp(-PI / 2.0) d0, d1;
    h d1;
    cp(-PI / 4.0) d0, d2;
    cp(-PI / 2.0) d1, d2;
    h d2;
    cp(-PI / 8.0) d0, d3;
    cp(-PI / 4.0) d1, d3;
    cp(-PI / 2.0) d2, d3;
    h d3;
}

// 1. Transform to Fourier eigenbasis: (I x F_N)
qft4 q[0], q[1], q[2], q[3];

// 2. Diagonal Fourier-symbol block encoding U_D via LCU ancilla
h anc[0];
cp(THETA_0) anc[0], q[0];
cp(THETA_1) anc[0], q[1];
cp(THETA_2) anc[0], q[2];
cp(THETA_3) anc[0], q[3];
x anc[0];
cp(-THETA_0) anc[0], q[0];
cp(-THETA_1) anc[0], q[1];
cp(-THETA_2) anc[0], q[2];
cp(-THETA_3) anc[0], q[3];
x anc[0];
h anc[0];

// 3. Transform back to position basis: (I x F_N^dagger)
iqft4 q[0], q[1], q[2], q[3];

// Postselection on c_anc == 0 projects onto A_N / alpha
c_anc[0] = measure anc[0];
c_q = measure q;
