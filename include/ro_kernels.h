/* SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-SnapKitty-Opaque-1.0
 * Copyright (C) 2026 Ahmad Ali Parr / SnapKitty Research Lab
 */
/* C23 view of the Fortran kernels in kernels/ro_kernels.f90 (ISO_C_BINDING). */
#ifndef RO_KERNELS_H
#define RO_KERNELS_H

/* are/aim: row-major n x n real and imaginary parts; w: n ascending eigenvalues. */
void ro_eigvalsh(int n, const double *are, const double *aim, double *w);
double ro_pairwise_sum(int n, const double *x);
double ro_mean(int n, const double *x);
double ro_std(int n, const double *x);
double ro_shannon(int n, const double *p);
double ro_vn_entropy(int n, const double *lam);
void ro_priority(int n, const double *ent, const double *nov, const double *prog,
                 const double *res, const double w[4], double *out);
/* sigma and t as decimal strings (parsed in REAL(16)). */
void ro_zeta_q(const char *sigma, const char *t, int slen, int tlen,
               double *zre, double *zim, double *zabs);
void ro_zetazeros(int kmax, double h, double *ts, double *rs);
void ro_zetazero(int k, double h, double *t, double *resid);

#endif
