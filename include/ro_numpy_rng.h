/* SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-SnapKitty-Opaque-1.0
 * Copyright (C) 2026 Ahmad Ali Parr / SnapKitty Research Lab
 */
/* numpy.random.default_rng(seed): SeedSequence -> PCG64 -> ziggurat standard_normal. */
#ifndef RO_NUMPY_RNG_H
#define RO_NUMPY_RNG_H
#include <stdint.h>

__extension__ typedef unsigned __int128 ro_u128;
typedef struct { ro_u128 state, inc; } ro_pcg64;

void ro_pcg64_seed(ro_pcg64 *g, uint32_t seed);
uint64_t ro_pcg64_next(ro_pcg64 *g);
double ro_standard_normal(ro_pcg64 *g);

#endif
