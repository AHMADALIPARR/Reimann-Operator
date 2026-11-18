OPENQASM 3.0;
include "stdgates.inc";

// SOVEREIGN-RH-LOCK: Periodic-Diagonal Block Encoding (n = 4 data qubits, N = 16)
// Implements D_cos |j> = cos(omega * j + phi) |j> = (V_{omega,phi} + V_{omega,phi}^dagger)/2 |j>
// Exact 1-ancilla LCU block encoding with subnormalization alpha = 1 and O(n) gates.

const float[64] OMEGA = 0.37;
const float[64] PHI   = 0.50;

qubit[1] anc;
qubit[4] q;
bit[1] c_anc;
bit[4] c_q;

// Prepare equal superposition on ancilla: H|0> = (|0> + |1>) / sqrt(2)
h anc[0];

// Controlled V_{omega, phi} on |0>_anc: flip ancilla to trigger on |0>
x anc[0];
p(PHI) anc[0];
cp(OMEGA)       anc[0], q[0];
cp(2.0 * OMEGA) anc[0], q[1];
cp(4.0 * OMEGA) anc[0], q[2];
cp(8.0 * OMEGA) anc[0], q[3];
x anc[0];

// Controlled V_{omega, phi}^dagger on |1>_anc
p(-PHI) anc[0];
cp(-OMEGA)       anc[0], q[0];
cp(-2.0 * OMEGA) anc[0], q[1];
cp(-4.0 * OMEGA) anc[0], q[2];
cp(-8.0 * OMEGA) anc[0], q[3];

// Uncompute ancilla Hadamard: (H x I)
h anc[0];

// Measuring c_anc == 0 heralds D_cos |psi> with normalization alpha = 1
c_anc[0] = measure anc[0];
c_q = measure q;
