/* SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-SnapKitty-Opaque-1.0
 * Copyright (C) 2026 Ahmad Ali Parr / SnapKitty Research Lab
 */
#include "ro_numpy_rng.h"
#include "ro_ziggurat_tables.h"

#include <math.h>

/* SeedSequence constants (numpy/random/bit_generator.pyx). */
#define INIT_A 0x43b0d7e5u
#define MULT_A 0x931e8875u
#define INIT_B 0x8b51f9ddu
#define MULT_B 0x58f38dedu
#define MIX_MULT_L 0xca01f9ddu
#define MIX_MULT_R 0x4973f715u
#define XSHIFT 16

static uint32_t hashmix(uint32_t value, uint32_t *hc) {
    value ^= *hc;
    *hc *= MULT_A;
    value *= *hc;
    value ^= value >> XSHIFT;
    return value;
}
static uint32_t mix(uint32_t x, uint32_t y) {
    uint32_t r = MIX_MULT_L * x - MIX_MULT_R * y;
    r ^= r >> XSHIFT;
    return r;
}

void ro_pcg64_seed(ro_pcg64 *g, uint32_t seed) {
    uint32_t pool[4];
    uint32_t hc = INIT_A;
    pool[0] = hashmix(seed, &hc);
    for (int i = 1; i < 4; ++i) pool[i] = hashmix(0, &hc);
    for (int s = 0; s < 4; ++s)
        for (int d = 0; d < 4; ++d)
            if (s != d) pool[d] = mix(pool[d], hashmix(pool[s], &hc));
    uint32_t w[8];
    uint32_t hb = INIT_B;
    for (int i = 0; i < 8; ++i) {
        uint32_t v = pool[i % 4];
        v ^= hb;
        hb *= MULT_B;
        v *= hb;
        v ^= v >> XSHIFT;
        w[i] = v;
    }
    uint64_t s64[4];
    for (int i = 0; i < 4; ++i) s64[i] = (uint64_t)w[2 * i] | ((uint64_t)w[2 * i + 1] << 32);
    ro_u128 initstate = ((ro_u128)s64[0] << 64) | s64[1];
    ro_u128 initseq = ((ro_u128)s64[2] << 64) | s64[3];
    g->state = 0;
    g->inc = (initseq << 1) | 1u;
    (void)ro_pcg64_next(g);
    g->state += initstate;
    (void)ro_pcg64_next(g);
}

uint64_t ro_pcg64_next(ro_pcg64 *g) {
    const ro_u128 mult = ((ro_u128)0x2360ED051FC65DA4ULL << 64) | 0x4385DF649FCCF645ULL;
    g->state = g->state * mult + g->inc;
    uint64_t hi = (uint64_t)(g->state >> 64), lo = (uint64_t)g->state;
    uint64_t x = hi ^ lo;
    unsigned rot = (unsigned)(hi >> 58);
    return (x >> rot) | (x << ((64u - rot) & 63u));
}

static double next_double(ro_pcg64 *g) { return (double)(ro_pcg64_next(g) >> 11) * (1.0 / 9007199254740992.0); }

double ro_standard_normal(ro_pcg64 *g) {
    const double r_ = 3.6541528853610088, inv_r = 0.27366123732975828;
    for (;;) {
        uint64_t r = ro_pcg64_next(g);
        int idx = (int)(r & 0xff);
        r >>= 8;
        int sign = (int)(r & 0x1);
        uint64_t rabs = (r >> 1) & 0x000fffffffffffffULL;
        double x = (double)rabs * wi_double[idx];
        if (sign & 0x1) x = -x;
        if (rabs < ki_double[idx]) return x;
        if (idx == 0) {
            for (;;) {
                double xx = -inv_r * log1p(-next_double(g));
                double yy = -log1p(-next_double(g));
                if (yy + yy > xx * xx) return ((rabs >> 8) & 0x1) ? -(r_ + xx) : r_ + xx;
            }
        } else {
            if (((fi_double[idx - 1] - fi_double[idx]) * next_double(g) + fi_double[idx]) < exp(-0.5 * x * x)) return x;
        }
    }
}
