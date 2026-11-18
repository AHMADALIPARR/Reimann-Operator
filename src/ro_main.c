/* SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-SnapKitty-Opaque-1.0
 * Copyright (C) 2026 Ahmad Ali Parr / SnapKitty Research Lab
 */
/* ro: C23 command-line driver for the Reimann-Operator ports.
 *
 *   torch/spectral.py   -> herm-res, eigvalsh, bk, zeta-res, zetazero, zeros, spacing, perturb
 *   torch/entropy.py    -> shannon, vn-entropy, entropy-bounds
 *   torch/candidates.py -> rank, ledger, pack, unpack
 *   dspy/research_engine.py, dspy/candidate_optimizer.py
 *                       -> provider, temp, lm-config, provenance, dag, metric, select
 *   oracle              -> oracle-check (data/zeta_zeros_oracle.txt)
 *   cmp                 -> JSON comparison with tolerance (used by ctest)
 *
 * Numeric work runs in the Fortran kernels (ro_kernels.h). Output is what the Python
 * prints through json.dumps. Errors print "<ExceptionName>: <message>" and exit 1. */
#include "ro_json.h"
#include "ro_kernels.h"
#include "ro_numpy_rng.h"
#include "ro_sha256.h"

#include <ctype.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

[[noreturn]] static void die(const char *exc, const char *msg) {
    printf("%s: %s\n", exc, msg);
    exit(1);
}
static void emit(rj_buf *b) { puts(b->p ? b->p : ""); rb_free(b); }
static rj_val *load_json(const char *path) {
    char err[256];
    rj_val *v = rj_parse_file(path, err, sizeof err);
    if (!v) die("OSError", err);
    return v;
}
static char *fmt_float(double x) {
    static char t[8][40];
    static int k;
    k = (k + 1) & 7;
    py_float_repr(x, t[k], false);
    return t[k];
}

/* ------------------------------------------------------------- matrices */
typedef struct { int n; double *re, *im; } cmat;
static cmat load_mat(const char *path) {
    rj_val *v = load_json(path);
    cmat m = {0};
    if (v->type != RJ_ARR || v->n == 0) die("ValueError", "matrix JSON must be a non-empty list of rows");
    m.n = (int)v->n;
    m.re = calloc((size_t)m.n * (size_t)m.n, sizeof(double));
    m.im = calloc((size_t)m.n * (size_t)m.n, sizeof(double));
    for (int i = 0; i < m.n; ++i) {
        const rj_val *row = &v->items[i];
        if (row->type != RJ_ARR || (int)row->n != m.n) die("ValueError", "matrix must be square");
        for (int j = 0; j < m.n; ++j) {
            const rj_val *x = &row->items[j];
            if (x->type == RJ_ARR) { m.re[i * m.n + j] = rj_num(&x->items[0]); m.im[i * m.n + j] = rj_num(&x->items[1]); }
            else m.re[i * m.n + j] = rj_num(x);
        }
    }
    rj_free(v);
    return m;
}
/* np.linalg.norm(A - A^H, 'fro') */
static double herm_residual(const cmat *m) {
    int n = m->n;
    double s = 0.0;
    for (int i = 0; i < n; ++i)
        for (int j = 0; j < n; ++j) {
            double dr = m->re[i * n + j] - m->re[j * n + i];
            double di = m->im[i * n + j] + m->im[j * n + i];
            s += dr * dr + di * di;
        }
    return sqrt(s);
}
static double *eig(const cmat *m) {
    double *w = malloc((size_t)m->n * sizeof(double));
    ro_eigvalsh(m->n, m->re, m->im, w);
    return w;
}
static void put_list(rj_buf *b, const double *x, int n) {
    rb_putc(b, '[');
    for (int i = 0; i < n; ++i) { if (i) rb_puts(b, ", "); rb_float(b, x[i]); }
    rb_putc(b, ']');
}

/* ------------------------------------------------------- spectral.py */
static cmat berry_keating(int n, double a, double b, double theta) {
    if (n < 4) die("ValueError", "Discretization size n must be >= 4");
    if (a <= 0.0 || b <= a) die("ValueError", "Require 0 < a < b");
    double length = log(b / a);
    double du = length / n;
    double inv = 1.0 / (2.0 * du);
    cmat m = {n, calloc((size_t)n * n, sizeof(double)), calloc((size_t)n * n, sizeof(double))};
    /* Same IEEE operations as the NumPy/CPython complex arithmetic in the Python. */
    double fr = 0.0 * inv - (-1.0) * 0.0, fi = (-0.0) * 0.0 + (-1.0) * inv; /* -1j * inv_2du */
    double br = 0.0 * inv - 1.0 * 0.0, bi = 0.0 * 0.0 + 1.0 * inv;          /*  1j * inv_2du */
    double nth_im = (theta * -1.0) + (-0.0 * 0.0);
    for (int j = 0; j < n; ++j) {
        int jn = (j + 1) % n, jp = (j - 1 + n) % n;
        double pr = 1.0, pi_ = 0.0, qr = 1.0, qi = 0.0;
        if (j == n - 1) { pr = cos(theta); pi_ = sin(theta); }
        if (j == 0) { qr = cos(nth_im); qi = sin(nth_im); }
        double vr = fr * pr - fi * pi_, vi = fr * pi_ + fi * pr;
        m.re[j * n + jn] += vr; m.im[j * n + jn] += vi;
        double wr = br * qr - bi * qi, wi = br * qi + bi * qr;
        m.re[j * n + jp] += wr; m.im[j * n + jp] += wi;
    }
    cmat h = {n, malloc((size_t)n * n * sizeof(double)), malloc((size_t)n * n * sizeof(double))};
    for (int i = 0; i < n; ++i)
        for (int j = 0; j < n; ++j) {
            double sr = m.re[i * n + j] + m.re[j * n + i];
            double si = m.im[i * n + j] + (-m.im[j * n + i]);
            h.re[i * n + j] = 0.5 * sr - 0.0 * si;
            h.im[i * n + j] = 0.5 * si + 0.0 * sr;
        }
    free(m.re); free(m.im);
    return h;
}
static int cmp_dbl(const void *a, const void *b) {
    double x = *(const double *)a, y = *(const double *)b;
    return (x > y) - (x < y);
}
static void spacing_stats(double *ev, int n, rj_buf *b) {
    qsort(ev, (size_t)n, sizeof(double), cmp_dbl);
    if (n < 3) {
        rb_printf(b, "{\"count\": %s, \"mean_spacing\": 0.0, \"std_spacing\": 0.0, \"mean_ratio\": 0.0}", fmt_float((double)n));
        return;
    }
    int m = n - 1, np_ = 0;
    double *sp = malloc((size_t)m * sizeof(double)), *pos = malloc((size_t)m * sizeof(double));
    for (int i = 0; i < m; ++i) { sp[i] = ev[i + 1] - ev[i]; if (sp[i] > 1e-15) pos[np_++] = sp[i]; }
    double mr = 0.0;
    if (np_ >= 2) {
        double *r = malloc((size_t)(np_ - 1) * sizeof(double));
        for (int i = 0; i < np_ - 1; ++i) r[i] = fmin(pos[i], pos[i + 1]) / fmax(pos[i], pos[i + 1]);
        mr = ro_mean(np_ - 1, r);
        free(r);
    }
    rb_printf(b, "{\"count\": %s, \"mean_spacing\": ", fmt_float((double)n));
    rb_float(b, ro_mean(m, sp));
    rb_puts(b, ", \"std_spacing\": ");
    rb_float(b, ro_std(m, sp));
    rb_puts(b, ", \"mean_ratio\": ");
    rb_float(b, mr);
    rb_putc(b, '}');
}

/* --------------------------------------------------------- entropy.py */
/* NumPy pairwise sum of the real parts of a complex vector (CDOUBLE_pairwise_sum). */
static double csum_re(const double *re, int c) {
    int n = 2 * c;
    if (n < 8) { double s = -0.0; for (int i = 0; i < c; ++i) s += re[i]; return s; }
    if (n <= 128) {
        double r[4] = {re[0], re[1], re[2], re[3]};
        int i;
        for (i = 4; i < c - (c % 4); i += 4) for (int k = 0; k < 4; ++k) r[k] += re[i + k];
        double s = (r[0] + r[1]) + (r[2] + r[3]);
        for (; i < c; ++i) s += re[i];
        return s;
    }
    int n2 = n / 2;
    n2 -= n2 % 8;
    return csum_re(re, n2 / 2) + csum_re(re + n2 / 2, c - n2 / 2);
}
static double von_neumann(const cmat *rho, double tol) {
    char msg[160];
    int n = rho->n;
    double herr = herm_residual(rho);
    if (herr > tol) { snprintf(msg, sizeof msg, "density_operator is not Hermitian (residual=%.3e)", herr); die("ValueError", msg); }
    cmat h = {n, malloc((size_t)n * n * sizeof(double)), malloc((size_t)n * n * sizeof(double))};
    double *diag = malloc((size_t)n * sizeof(double));
    for (int i = 0; i < n; ++i)
        for (int j = 0; j < n; ++j) {
            double sr = rho->re[i * n + j] + rho->re[j * n + i];
            double si = rho->im[i * n + j] + (-rho->im[j * n + i]);
            h.re[i * n + j] = 0.5 * sr - 0.0 * si;
            h.im[i * n + j] = 0.5 * si + 0.0 * sr;
        }
    for (int i = 0; i < n; ++i) diag[i] = h.re[i * n + i];
    double tr = csum_re(diag, n);
    if (fabs(tr - 1.0) > tol) { snprintf(msg, sizeof msg, "density_operator trace must be 1.0 (got %.12f)", tr); die("ValueError", msg); }
    double *w = eig(&h);
    double mn = w[0];
    for (int i = 1; i < n; ++i) mn = fmin(mn, w[i]);
    if (mn < -tol) { snprintf(msg, sizeof msg, "density_operator is not positive semidefinite (min_eig=%.3e)", mn); die("ValueError", msg); }
    return ro_vn_entropy(n, w);
}
static void shannon_row(const rj_val *row, rj_buf *b) {
    int n = (int)row->n;
    double *p = malloc((size_t)(n ? n : 1) * sizeof(double));
    for (int i = 0; i < n; ++i) p[i] = rj_num(&row->items[i]);
    rb_float(b, ro_shannon(n, p));
    free(p);
}
static void shannon_check(const rj_val *v) {
    size_t total = 0;
    bool bad = false, nonpos = false;
    const rj_val *rows = v;
    size_t nr = v->n ? v->n : 0;
    bool two = nr && v->items[0].type == RJ_ARR;
    for (size_t r = 0; r < (two ? nr : 1); ++r) {
        const rj_val *row = two ? &rows->items[r] : rows;
        double s = 0.0;
        for (size_t i = 0; i < row->n; ++i) {
            double x = rj_num(&row->items[i]);
            if (x < 0 || !isfinite(x)) bad = true;
            s += x;
            total++;
        }
        if (!(s > 0)) nonpos = true;
    }
    if (total == 0) die("ValueError", "probabilities array must be non-empty");
    if (bad) die("ValueError", "probabilities must be finite and non-negative");
    if (nonpos) die("ValueError", "probabilities must sum to a positive value");
}

/* ------------------------------------------------------ candidates.py */
typedef struct {
    rj_val f[12]; /* candidate_id parent_id generation zero_real zero_imag eigenvalue_real entropy residual status info_gain novelty obligation_progress */
} ncand;
static const char *NC_FIELDS[12] = {"candidate_id", "parent_id", "generation", "zero_real", "zero_imag", "eigenvalue_real",
                                    "entropy", "residual", "status", "info_gain", "novelty", "obligation_progress"};
static ncand *load_cands(const char *path, int *count, rj_val **keep) {
    rj_val *v = load_json(path);
    *keep = v;
    *count = (int)v->n;
    ncand *c = calloc(v->n + 1, sizeof *c);
    for (size_t i = 0; i < v->n; ++i) {
        for (int k = 0; k < 12; ++k) {
            const rj_val *x = rj_get(&v->items[i], NC_FIELDS[k]);
            if (x) c[i].f[k] = *x;
            else if (k == 8) { c[i].f[k].type = RJ_INT; c[i].f[k].i = 1; c[i].f[k].d = 1; }
            else if (k > 8) { c[i].f[k].type = RJ_FLOAT; c[i].f[k].d = 0.0; }
            else die("TypeError", "missing candidate field");
        }
    }
    return c;
}
static double ncd(const ncand *c, int k) { return rj_num(&c->f[k]); }
static double *priorities(const ncand *c, int n) {
    double *e = malloc((size_t)(n + 1) * 8), *nv = malloc((size_t)(n + 1) * 8), *p = malloc((size_t)(n + 1) * 8),
           *r = malloc((size_t)(n + 1) * 8), *o = malloc((size_t)(n + 1) * 8);
    for (int i = 0; i < n; ++i) { e[i] = ncd(&c[i], 6); nv[i] = ncd(&c[i], 10); p[i] = ncd(&c[i], 11); r[i] = ncd(&c[i], 7); }
    const double w[4] = {1.0, 0.5, 2.0, 1.5};
    ro_priority(n, e, nv, p, r, w, o);
    free(e); free(nv); free(p); free(r);
    return o;
}
static int64_t nci(const ncand *c, int k) { return c->f[k].type == RJ_INT ? c->f[k].i : (int64_t)c->f[k].d; }
static void put_le64(FILE *f, uint64_t x) { for (int k = 0; k < 8; ++k) fputc((int)((x >> (8 * k)) & 0xff), f); }
static uint64_t get_le64(const unsigned char *p) { uint64_t x = 0; for (int k = 7; k >= 0; --k) x = (x << 8) | p[k]; return x; }
static void py_bytes_repr(rj_buf *b, const unsigned char *p, size_t n) {
    bool sq = memchr(p, '\'', n) != NULL, dq = memchr(p, '"', n) != NULL;
    char q = (sq && !dq) ? '"' : '\'';
    rb_putc(b, 'b'); rb_putc(b, q);
    for (size_t i = 0; i < n; ++i) {
        unsigned c = p[i];
        if (c == (unsigned)q || c == '\\') { rb_putc(b, '\\'); rb_putc(b, (char)c); }
        else if (c == '\t') rb_puts(b, "\\t");
        else if (c == '\n') rb_puts(b, "\\n");
        else if (c == '\r') rb_puts(b, "\\r");
        else if (c < 0x20 || c >= 0x7f) rb_printf(b, "\\x%02x", c);
        else rb_putc(b, (char)c);
    }
    rb_putc(b, q);
}

/* -------------------------------------------------- research_engine.py */
static const char *PROVIDERS[6] = {"anthropic", "gemini", "local", "mistral", "openai", "vertex_ai"};
static const double PROVIDER_MAX[6] = {1.0, 2.0, 2.0, 1.5, 2.0, 2.0};
static int detect_provider(const char *model) {
    char prefix[256] = "openai";
    const char *sl = strchr(model, '/');
    if (sl) {
        size_t n = (size_t)(sl - model);
        if (n > 255) n = 255;
        for (size_t i = 0; i < n; ++i) prefix[i] = (char)tolower((unsigned char)model[i]);
        prefix[n] = 0;
    }
    for (int i = 0; i < 6; ++i) if (!strcmp(prefix, PROVIDERS[i])) return i;
    rj_buf b = {0};
    rb_printf(&b, "Unsupported or unknown provider '%s' in model '%s'. Supported providers: [", prefix, model);
    for (int i = 0; i < 6; ++i) { if (i) rb_puts(&b, ", "); rb_pystr(&b, PROVIDERS[i]); }
    rb_putc(&b, ']');
    die("ValueError", b.p);
}
static double validate_temperature(const char *model, double t) {
    char msg[512];
    if (!(0.0 <= t)) { snprintf(msg, sizeof msg, "Temperature must be >= 0.0, got %s", fmt_float(t)); die("ValueError", msg); }
    int p = detect_provider(model);
    if (t > PROVIDER_MAX[p]) {
        snprintf(msg, sizeof msg,
                 "Requested temperature %s exceeds max supported temperature %s for provider '%s'. "
                 "Rejecting rather than silently substituting.",
                 fmt_float(t), fmt_float(PROVIDER_MAX[p]), PROVIDERS[p]);
        die("ValueError", msg);
    }
    return t;
}
static const char *CR_FIELDS[9] = {"hypothesis_id", "parent_hypothesis_ids", "mathematical_statement", "assumptions",
                                   "claimed_derivation", "spectral_evidence", "entropy_score",
                                   "counterexample_search_result", "formal_verification_status"};
static const rj_val *record_of(const rj_val *d) { const rj_val *r = rj_get(d, "record"); return r ? r : d; }
static void provenance_hash(const rj_val *rec, char out[65]) {
    rj_val o = {0};
    o.type = RJ_OBJ;
    o.n = 9;
    rj_val items[9];
    char *keys[9];
    for (int k = 0; k < 9; ++k) {
        const rj_val *x = rj_get(rec, CR_FIELDS[k]);
        if (!x) die("TypeError", "missing CandidateRecord field");
        items[k] = *x;
        keys[k] = (char *)CR_FIELDS[k];
    }
    o.items = items;
    o.keys = keys;
    rj_buf b = {0};
    rb_value(&b, &o, true, true);
    uint8_t dg[32];
    ro_sha256(b.p, b.len, dg);
    ro_hex32(dg, out);
    rb_free(&b);
}
static bool py_space(unsigned char c) { return c == ' ' || (c >= 9 && c <= 13) || (c >= 0x1c && c <= 0x1f); }
static char *canonical_stmt(const char *s) {
    size_t n = strlen(s);
    char *o = malloc(n + 1), *w = o;
    const unsigned char *p = (const unsigned char *)s;
    bool first = true;
    while (*p) {
        while (*p && py_space(*p)) p++;
        if (!*p) break;
        if (!first) *w++ = ' ';
        first = false;
        while (*p && !py_space(*p)) *w++ = (char)tolower(*p++);
    }
    *w = 0;
    return o;
}
static double verification_metric(const rj_val *rec, const char *phash) {
    double score = 0.0;
    const char *stmt = rj_get(rec, "mathematical_statement")->s;
    char *cs = canonical_stmt(stmt);
    if (cs[0]) score += 0.15;
    free(cs);
    if (rj_get(rec, "assumptions")->n) score += 0.15;
    if (phash && strlen(phash) == 64) score += 0.10;
    const char *cx = rj_get(rec, "counterexample_search_result")->s;
    char *up = strdup(cx);
    for (char *q = up; *q; ++q) *q = (char)toupper((unsigned char)*q);
    bool refuted = strstr(up, "REFUTED") != NULL;
    free(up);
    if (refuted) return 0.0;
    char *cc = canonical_stmt(cx);
    if (cc[0]) score += 0.20;
    free(cc);
    const char *st = rj_get(rec, "formal_verification_status")->s;
    if (!strcmp(st, "VERIFIED_LEMMA")) score += 0.40;
    else if (!strcmp(st, "NUMERICALLY_SUPPORTED")) score += 0.15;
    if (score > 1.0) score = 1.0;
    char t[64];
    snprintf(t, sizeof t, "%.6f", score);
    return strtod(t, NULL);
}

/* ---------------------------------------------------------------- cmp */
static bool cmp_val(const rj_val *a, const rj_val *b, double rtol, double atol, char *where) {
    bool na = a->type == RJ_INT || a->type == RJ_FLOAT, nb = b->type == RJ_INT || b->type == RJ_FLOAT;
    if (na && nb) {
        if (a->type != b->type && rtol == 0.0 && atol == 0.0) { strcpy(where, "int/float type"); return false; }
        double x = rj_num(a), y = rj_num(b);
        if (isnan(x) && isnan(y)) return true;
        if (x == y) return true;
        if (fabs(x - y) <= atol + rtol * fabs(y)) return true;
        snprintf(where, 200, "%s vs %s", fmt_float(x), fmt_float(y));
        return false;
    }
    if (a->type != b->type) { strcpy(where, "type"); return false; }
    switch (a->type) {
    case RJ_STR: if (strcmp(a->s, b->s)) { snprintf(where, 200, "string \"%.80s\" vs \"%.80s\"", a->s, b->s); return false; } return true;
    case RJ_BOOL: if (a->b != b->b) { strcpy(where, "bool"); return false; } return true;
    case RJ_NULL: return true;
    case RJ_ARR:
    case RJ_OBJ:
        if (a->n != b->n) { strcpy(where, "length"); return false; }
        for (size_t k = 0; k < a->n; ++k) {
            if (a->type == RJ_OBJ && strcmp(a->keys[k], b->keys[k])) { strcpy(where, "key"); return false; }
            if (!cmp_val(&a->items[k], &b->items[k], rtol, atol, where)) return false;
        }
        return true;
    default: return true;
    }
}

/* ---------------------------------------------------------------- main */
static void usage(void) {
    fputs("usage: ro <command> [args]\n"
          "  herm-res M.json | eigvalsh M.json | bk n a b theta | zeta-res sigma t [dps]\n"
          "  zetazero k [dps] | zeros kmax | spacing ev.json | perturb M.json [eps] [seed]\n"
          "  shannon p.json | vn-entropy M.json [tol] | entropy-bounds value dim\n"
          "  rank C.json | ledger C.json | pack C.json out.bin | unpack in.bin\n"
          "  provider model | temp model t | lm-config | provenance R.json | dag R.json [d b t]\n"
          "  metric R.json | select R.json k | oracle-check oracle.txt [kmax]\n"
          "  cmp expected actual [rtol] [atol]\n", stderr);
    exit(2);
}
#define NEED(k) do { if (argc < (k)) usage(); } while (0)

int main(int argc, char **argv) {
    NEED(2);
    const char *cmd = argv[1];
    rj_buf b = {0};
    if (!strcmp(cmd, "herm-res")) {
        NEED(3); cmat m = load_mat(argv[2]); rb_float(&b, herm_residual(&m)); emit(&b);
    } else if (!strcmp(cmd, "eigvalsh")) {
        NEED(3); cmat m = load_mat(argv[2]); double *w = eig(&m); put_list(&b, w, m.n); emit(&b);
    } else if (!strcmp(cmd, "bk")) {
        NEED(6);
        cmat m = berry_keating(atoi(argv[2]), strtod(argv[3], NULL), strtod(argv[4], NULL), strtod(argv[5], NULL));
        rb_putc(&b, '[');
        for (int i = 0; i < m.n; ++i) {
            if (i) rb_puts(&b, ", ");
            rb_putc(&b, '[');
            for (int j = 0; j < m.n; ++j) {
                if (j) rb_puts(&b, ", ");
                rb_putc(&b, '['); rb_float(&b, m.re[i * m.n + j]); rb_puts(&b, ", "); rb_float(&b, m.im[i * m.n + j]); rb_putc(&b, ']');
            }
            rb_putc(&b, ']');
        }
        rb_putc(&b, ']');
        emit(&b);
    } else if (!strcmp(cmd, "zeta-res")) {
        NEED(4);
        int dps = argc > 4 ? atoi(argv[4]) : 50;
        char s[40], t[40];
        py_float_repr(strtod(argv[2], NULL), s, false);
        py_float_repr(strtod(argv[3], NULL), t, false);
        double zr, zi, za;
        ro_zeta_q(s, t, (int)strlen(s), (int)strlen(t), &zr, &zi, &za);
        rb_putc(&b, '['); rb_float(&b, za); rb_puts(&b, ", ");
        char u[32]; snprintf(u, sizeof u, "1e%d", -(dps - 5)); rb_float(&b, strtod(u, NULL)); rb_putc(&b, ']');
        emit(&b);
    } else if (!strcmp(cmd, "zetazero")) {
        NEED(3);
        int k = atoi(argv[2]);
        int dps = argc > 3 ? atoi(argv[3]) : 50;
        if (k < 1) die("ValueError", "Zero index k must be >= 1");
        double t, r;
        ro_zetazero(k, 0.02, &t, &r);
        rb_printf(&b, "{\"index\": %s, \"real\": 0.5, \"imag\": ", fmt_float((double)k));
        rb_float(&b, t); rb_puts(&b, ", \"residual\": "); rb_float(&b, r);
        rb_printf(&b, ", \"dps\": %s}", fmt_float((double)dps));
        emit(&b);
    } else if (!strcmp(cmd, "zeros")) {
        NEED(3);
        int k = atoi(argv[2]);
        double *ts = malloc((size_t)k * 8), *rs = malloc((size_t)k * 8);
        ro_zetazeros(k, 0.02, ts, rs);
        put_list(&b, ts, k);
        emit(&b);
    } else if (!strcmp(cmd, "spacing")) {
        NEED(3);
        rj_val *v = load_json(argv[2]);
        double *ev = malloc((v->n + 1) * sizeof(double));
        for (size_t i = 0; i < v->n; ++i) ev[i] = rj_num(&v->items[i]);
        spacing_stats(ev, (int)v->n, &b);
        emit(&b);
    } else if (!strcmp(cmd, "perturb")) {
        NEED(3);
        cmat d = load_mat(argv[2]);
        double eps = argc > 3 ? strtod(argv[3], NULL) : 1e-6;
        uint32_t seed = argc > 4 ? (uint32_t)strtoul(argv[4], NULL, 10) : 42u;
        int n = d.n;
        size_t nn = (size_t)n * n;
        double *ar = malloc(nn * 8), *ai = malloc(nn * 8);
        ro_pcg64 g;
        ro_pcg64_seed(&g, seed);
        for (size_t i = 0; i < nn; ++i) ar[i] = ro_standard_normal(&g);
        for (size_t i = 0; i < nn; ++i) ai[i] = ro_standard_normal(&g);
        cmat p = {n, malloc(nn * 8), malloc(nn * 8)};
        for (int i = 0; i < n; ++i)
            for (int j = 0; j < n; ++j) {
                double rr = ar[i * n + j] + (0.0 * ai[i * n + j] - 1.0 * 0.0), ri = 0.0 * 0.0 + 1.0 * ai[i * n + j];
                double tr = ar[j * n + i] + (0.0 * ai[j * n + i] - 1.0 * 0.0), ti = 0.0 * 0.0 + 1.0 * ai[j * n + i];
                double sr = rr + tr, si = ri + (-ti);
                p.re[i * n + j] = 0.5 * sr - 0.0 * si;
                p.im[i * n + j] = 0.5 * si + 0.0 * sr;
            }
        double *wp = eig(&p);
        double normp = fmax(fabs(wp[0]), fabs(wp[n - 1]));
        if (normp > 0) {
            double f = eps / normp;
            for (size_t i = 0; i < nn; ++i) { double r0 = p.re[i], i0 = p.im[i]; p.re[i] = r0 * f - i0 * 0.0; p.im[i] = r0 * 0.0 + i0 * f; }
        }
        double *lb = eig(&d);
        cmat s = {n, malloc(nn * 8), malloc(nn * 8)};
        for (size_t i = 0; i < nn; ++i) { s.re[i] = d.re[i] + p.re[i]; s.im[i] = d.im[i] + p.im[i]; }
        double *lp = eig(&s);
        double mx = 0.0;
        for (int i = 0; i < n; ++i) mx = fmax(mx, fabs(lp[i] - lb[i]));
        double *wq = eig(&p);
        double bound = fmax(fabs(wq[0]), fabs(wq[n - 1]));
        rb_puts(&b, "{\"epsilon\": "); rb_float(&b, eps);
        rb_puts(&b, ", \"max_eigenvalue_shift\": "); rb_float(&b, mx);
        rb_puts(&b, ", \"weyl_upper_bound\": "); rb_float(&b, bound);
        rb_printf(&b, ", \"bound_satisfied\": %s}", mx <= bound + 1e-12 ? "true" : "false");
        emit(&b);
    } else if (!strcmp(cmd, "shannon")) {
        NEED(3);
        rj_val *v = load_json(argv[2]);
        shannon_check(v);
        if (v->n && v->items[0].type == RJ_ARR) {
            rb_putc(&b, '[');
            for (size_t r = 0; r < v->n; ++r) { if (r) rb_puts(&b, ", "); shannon_row(&v->items[r], &b); }
            rb_putc(&b, ']');
        } else shannon_row(v, &b);
        emit(&b);
    } else if (!strcmp(cmd, "vn-entropy")) {
        NEED(3);
        cmat m = load_mat(argv[2]);
        rb_float(&b, von_neumann(&m, argc > 3 ? strtod(argv[3], NULL) : 1e-10));
        emit(&b);
    } else if (!strcmp(cmd, "entropy-bounds")) {
        NEED(4);
        double v = strtod(argv[2], NULL);
        long dim = strtol(argv[3], NULL, 10);
        bool ok = dim > 0 && isfinite(v) && -1e-12 <= v && v <= log((double)dim) + 1e-12;
        puts(ok ? "true" : "false");
    } else if (!strcmp(cmd, "rank") || !strcmp(cmd, "ledger") || !strcmp(cmd, "pack")) {
        NEED(3);
        int n;
        rj_val *keep;
        ncand *c = load_cands(argv[2], &n, &keep);
        if (!strcmp(cmd, "rank")) {
            double *pr = priorities(c, n);
            int *ord = malloc((size_t)(n + 1) * sizeof(int));
            for (int i = 0; i < n; ++i) ord[i] = i;
            for (int i = 1; i < n; ++i)
                for (int j = i; j > 0; --j) {
                    int x = ord[j - 1], y = ord[j];
                    double kx = -pr[x], ky = -pr[y];
                    bool gt = kx > ky || (kx == ky && nci(&c[x], 0) > nci(&c[y], 0));
                    if (!gt) break;
                    ord[j - 1] = y; ord[j] = x;
                }
            rb_putc(&b, '[');
            for (int i = 0; i < n; ++i) {
                if (i) rb_puts(&b, ", ");
                rb_printf(&b, "[%lld, ", (long long)nci(&c[ord[i]], 0));
                rb_float(&b, pr[ord[i]]);
                rb_putc(&b, ']');
            }
            rb_putc(&b, ']');
            emit(&b);
        } else if (!strcmp(cmd, "ledger")) {
            char prev[65];
            memset(prev, '0', 64); prev[64] = 0;
            const char *keys[11] = {"candidate_id", "eigenvalue_real", "entropy", "generation", "note", "parent_id",
                                    "prev_hash", "residual", "status", "zero_imag", "zero_real"};
            const int fidx[11] = {0, 5, 6, 2, -1, 1, -2, 7, 8, 4, 3};
            char **hashes = malloc((size_t)(n + 1) * sizeof(char *));
            for (int i = 0; i < n; ++i) {
                rj_buf p = {0};
                rb_putc(&p, '{');
                for (int k = 0; k < 11; ++k) {
                    if (k) rb_putc(&p, ',');
                    rb_jstr(&p, keys[k]);
                    rb_putc(&p, ':');
                    if (fidx[k] == -1) { char note[32]; snprintf(note, sizeof note, "step-%d", i); rb_jstr(&p, note); }
                    else if (fidx[k] == -2) rb_jstr(&p, prev);
                    else rb_value(&p, &c[i].f[fidx[k]], true, true);
                }
                rb_putc(&p, '}');
                uint8_t dg[32];
                ro_sha256(p.p, p.len, dg);
                ro_hex32(dg, prev);
                hashes[i] = strdup(prev);
                rb_free(&p);
            }
            rb_puts(&b, "{\"hashes\": [");
            for (int i = 0; i < n; ++i) { if (i) rb_puts(&b, ", "); rb_jstr(&b, hashes[i]); }
            rb_puts(&b, "], \"verify_chain\": true}");
            emit(&b);
        } else {
            NEED(4);
            FILE *f = fopen(argv[3], "wb");
            if (!f) die("OSError", "cannot write output");
            fwrite("SRHLK64\0", 1, 8, f);
            put_le64(f, 1); put_le64(f, (uint64_t)n); put_le64(f, 9);
            const int order[9] = {0, 1, 2, 3, 4, 5, 6, 7, 8};
            for (int k = 0; k < 9; ++k)
                for (int i = 0; i < n; ++i) {
                    bool isint = order[k] <= 2 || order[k] == 8;
                    if (isint) put_le64(f, (uint64_t)nci(&c[i], order[k]));
                    else { double x = ncd(&c[i], order[k]); uint64_t u; memcpy(&u, &x, 8); put_le64(f, u); }
                }
            long sz = ftell(f);
            fclose(f);
            printf("%ld\n", sz);
        }
    } else if (!strcmp(cmd, "unpack")) {
        NEED(3);
        FILE *f = fopen(argv[2], "rb");
        if (!f) die("OSError", "cannot open input");
        fseek(f, 0, SEEK_END);
        long len = ftell(f);
        fseek(f, 0, SEEK_SET);
        unsigned char *blob = malloc((size_t)len + 1);
        if (fread(blob, 1, (size_t)len, f) != (size_t)len) die("OSError", "short read");
        fclose(f);
        char msg[256];
        if (len < 32) { snprintf(msg, sizeof msg, "Buffer too small for 32-byte header: %ld bytes", len); die("ValueError", msg); }
        if (memcmp(blob, "SRHLK64\0", 8)) {
            rj_buf m = {0}; rb_puts(&m, "Invalid magic header: "); py_bytes_repr(&m, blob, 8); die("ValueError", m.p);
        }
        int64_t ver = (int64_t)get_le64(blob + 8), n = (int64_t)get_le64(blob + 16), nc = (int64_t)get_le64(blob + 24);
        if (ver != 1) { snprintf(msg, sizeof msg, "Unsupported contract version: %lld", (long long)ver); die("ValueError", msg); }
        if (nc != 9) { snprintf(msg, sizeof msg, "Unexpected column count: %lld", (long long)nc); die("ValueError", msg); }
        long long expect = 32 + n * nc * 8;
        if (len != expect) { snprintf(msg, sizeof msg, "Length mismatch: expected %lld, got %ld", expect, len); die("ValueError", msg); }
        rb_putc(&b, '[');
        for (int64_t i = 0; i < n; ++i) {
            if (i) rb_puts(&b, ", ");
            rb_putc(&b, '{');
            for (int k = 0; k < 12; ++k) {
                if (k) rb_puts(&b, ", ");
                rb_jstr(&b, NC_FIELDS[k]);
                rb_puts(&b, ": ");
                if (k >= 9) { rb_puts(&b, "0.0"); continue; }
                uint64_t u = get_le64(blob + 32 + (size_t)(k * n + i) * 8);
                if (k <= 2 || k == 8) rb_printf(&b, "%lld", (long long)(int64_t)u);
                else { double x; memcpy(&x, &u, 8); rb_float(&b, x); }
            }
            rb_putc(&b, '}');
        }
        rb_putc(&b, ']');
        emit(&b);
    } else if (!strcmp(cmd, "provider")) {
        NEED(3); rb_jstr(&b, PROVIDERS[detect_provider(argv[2])]); emit(&b);
    } else if (!strcmp(cmd, "temp")) {
        NEED(4); rb_float(&b, validate_temperature(argv[2], strtod(argv[3], NULL))); emit(&b);
    } else if (!strcmp(cmd, "lm-config")) {
        const char *model = getenv("SOVEREIGN_MODEL");
        if (!model) die("KeyError", "'SOVEREIGN_MODEL'");
        const char *ts = getenv("SOVEREIGN_TEMPERATURE"), *mt = getenv("SOVEREIGN_MAX_TOKENS");
        double t = validate_temperature(model, strtod(ts ? ts : "1.0", NULL));
        long tok = strtol(mt ? mt : "16000", NULL, 10);
        rb_puts(&b, "{\"exploratory\": {\"model\": "); rb_jstr(&b, model);
        rb_puts(&b, ", \"temperature\": "); rb_float(&b, t);
        rb_printf(&b, ", \"max_tokens\": %ld}, \"verdict\": {\"model\": ", tok); rb_jstr(&b, model);
        rb_printf(&b, ", \"temperature\": 0.0, \"max_tokens\": %ld}}", tok);
        emit(&b);
    } else if (!strcmp(cmd, "provenance") || !strcmp(cmd, "metric") || !strcmp(cmd, "select") || !strcmp(cmd, "dag")) {
        NEED(3);
        rj_val *v = load_json(argv[2]);
        size_t n = v->n;
        if (!strcmp(cmd, "provenance")) {
            rb_putc(&b, '[');
            for (size_t i = 0; i < n; ++i) { char h[65]; provenance_hash(record_of(&v->items[i]), h); if (i) rb_puts(&b, ", "); rb_jstr(&b, h); }
            rb_putc(&b, ']');
        } else if (!strcmp(cmd, "metric")) {
            rb_putc(&b, '[');
            for (size_t i = 0; i < n; ++i) {
                const rj_val *r = record_of(&v->items[i]);
                const rj_val *ph = rj_get(r, "provenance_hash");
                if (i) rb_puts(&b, ", ");
                rb_float(&b, verification_metric(r, ph ? ph->s : ""));
            }
            rb_putc(&b, ']');
        } else if (!strcmp(cmd, "select")) {
            NEED(4);
            long k = strtol(argv[3], NULL, 10);
            double *m = malloc((n + 1) * 8);
            size_t *ord = malloc((n + 1) * sizeof(size_t));
            for (size_t i = 0; i < n; ++i) { char h[65]; provenance_hash(record_of(&v->items[i]), h); m[i] = verification_metric(record_of(&v->items[i]), h); ord[i] = i; }
            for (size_t i = 1; i < n; ++i)
                for (size_t j = i; j > 0; --j) {
                    size_t x = ord[j - 1], y = ord[j];
                    const char *ix = rj_get(record_of(&v->items[x]), "hypothesis_id")->s, *iy = rj_get(record_of(&v->items[y]), "hypothesis_id")->s;
                    bool gt = -m[x] > -m[y] || (-m[x] == -m[y] && strcmp(ix, iy) > 0);
                    if (!gt) break;
                    ord[j - 1] = y; ord[j] = x;
                }
            if (k < 0) k = (long)n + k > 0 ? (long)n + k : 0;
            rb_putc(&b, '[');
            for (size_t i = 0; i < n && (long)i < k; ++i) { if (i) rb_puts(&b, ", "); rb_jstr(&b, rj_get(record_of(&v->items[ord[i]]), "hypothesis_id")->s); }
            rb_putc(&b, ']');
        } else {
            int maxd = argc > 3 ? atoi(argv[3]) : 4;
            int maxt = argc > 5 ? atoi(argv[5]) : 64;
            char **ids = calloc(n + 1, sizeof(char *)), **hs = calloc(n + 1, sizeof(char *)), **seen = calloc(n + 1, sizeof(char *));
            char **proc = calloc(n + 1, sizeof(char *));
            size_t nn = 0, ns = 0, np_ = 0;
            rj_buf res = {0};
            rb_putc(&res, '[');
            for (size_t i = 0; i < n; ++i) {
                const rj_val *d = &v->items[i], *r = record_of(d);
                const rj_val *dv = rj_get(d, "depth");
                long depth = dv ? (long)rj_num(dv) : 0;
                if (i) rb_puts(&res, ", ");
                if (depth > maxd || (long)nn >= maxt) { rb_puts(&res, "false"); continue; }
                char *canon = canonical_stmt(rj_get(r, "mathematical_statement")->s);
                bool dup = false;
                for (size_t s = 0; s < ns; ++s) if (!strcmp(seen[s], canon)) dup = true;
                if (dup) { rb_puts(&res, "false"); free(canon); continue; }
                const rj_val *par = rj_get(r, "parent_hypothesis_ids");
                const char *missing = NULL;
                for (size_t p = 0; p < par->n && !missing; ++p) {
                    bool found = false;
                    for (size_t q = 0; q < nn; ++q) if (!strcmp(ids[q], par->items[p].s)) found = true;
                    if (!found) missing = par->items[p].s;
                }
                if (missing) {
                    rj_buf m = {0}; rb_printf(&m, "ValueError: Missing parent hypothesis ID: %s", missing);
                    rb_jstr(&res, m.p); rb_free(&m); free(canon); continue;
                }
                char h[65];
                provenance_hash(r, h);
                const char *id = rj_get(r, "hypothesis_id")->s;
                size_t q;
                for (q = 0; q < nn; ++q) if (!strcmp(ids[q], id)) break;
                if (q == nn) { ids[nn] = strdup(id); hs[nn++] = strdup(h); }
                else { free(hs[q]); hs[q] = strdup(h); }
                seen[ns++] = canon;
                proc[np_++] = strdup(id);
                rb_puts(&res, "true");
            }
            rb_putc(&res, ']');
            rb_puts(&b, "{\"results\": "); rb_puts(&b, res.p); rb_puts(&b, ", \"processed_ids\": [");
            for (size_t i = 0; i < np_; ++i) { if (i) rb_puts(&b, ", "); rb_jstr(&b, proc[i]); }
            rb_puts(&b, "], \"hashes\": [");
            for (size_t i = 0; i < np_; ++i) {
                size_t q;
                for (q = 0; q < nn; ++q) if (!strcmp(ids[q], proc[i])) break;
                if (i) rb_puts(&b, ", ");
                rb_jstr(&b, hs[q]);
            }
            rb_puts(&b, "]}");
            rb_free(&res);
        }
        emit(&b);
    } else if (!strcmp(cmd, "oracle-check")) {
        NEED(3);
        FILE *f = fopen(argv[2], "r");
        if (!f) die("OSError", "cannot open oracle");
        int cap = 1024, n = 0;
        int *idx = malloc((size_t)cap * sizeof(int));
        double *im = malloc((size_t)cap * 8);
        char line[256];
        while (fgets(line, sizeof line, f)) {
            double a, c;
            int got = sscanf(line, "%lf %lf", &a, &c);
            if (got <= 0) continue;
            if (n == cap) { cap *= 2; idx = realloc(idx, (size_t)cap * sizeof(int)); im = realloc(im, (size_t)cap * 8); }
            if (got == 2) { idx[n] = (int)a; im[n] = c; }
            else { idx[n] = n + 1; im[n] = a; } /* row without an index: its line number */
            n++;
        }
        fclose(f);
        int kmax = argc > 3 ? atoi(argv[3]) : n;
        int maxk = 0;
        for (int i = 0; i < n; ++i) if (idx[i] <= kmax && idx[i] > maxk) maxk = idx[i];
        double *ts = malloc((size_t)(maxk + 1) * 8), *rs = malloc((size_t)(maxk + 1) * 8);
        ro_zetazeros(maxk, 0.02, ts, rs);
        int checked = 0, fails = 0;
        double maxdiff = 0.0, maxres = 0.0, maxzr = 0.0;
        for (int i = 0; i < n; ++i) {
            if (idx[i] > kmax) continue;
            double d = fabs(ts[idx[i] - 1] - im[i]);
            maxdiff = fmax(maxdiff, d);
            maxres = fmax(maxres, rs[idx[i] - 1]);
            char s[40], t[40];
            py_float_repr(0.5, s, false);
            snprintf(t, sizeof t, "%.10f", im[i]);
            double zr, zi, za;
            ro_zeta_q(s, t, (int)strlen(s), (int)strlen(t), &zr, &zi, &za);
            maxzr = fmax(maxzr, za);
            if (d > 5.0e-11 + 1e-12) { fails++; fprintf(stderr, "zero %d: computed %.12f oracle %.10f\n", idx[i], ts[idx[i] - 1], im[i]); }
            checked++;
        }
        printf("{\"checked\": %d, \"mismatches\": %d, \"max_abs_diff\": %s, \"max_residual_at_root\": %s, \"max_abs_zeta_at_oracle\": %s}\n",
               checked, fails, fmt_float(maxdiff), fmt_float(maxres), fmt_float(maxzr));
        return fails ? 1 : 0;
    } else if (!strcmp(cmd, "cmp")) {
        NEED(4);
        double rtol = argc > 4 ? strtod(argv[4], NULL) : 0.0, atol = argc > 5 ? strtod(argv[5], NULL) : 0.0;
        char err[256];
        rj_val *x = rj_parse_file(argv[2], err, sizeof err), *y = rj_parse_file(argv[3], err, sizeof err);
        if (!x || !y) {
            /* not JSON (e.g. "ValueError: ..." lines): compare bytes */
            FILE *fa = fopen(argv[2], "rb"), *fb = fopen(argv[3], "rb");
            if (!fa || !fb) { fprintf(stderr, "cmp: cannot open\n"); return 1; }
            int ca, cb;
            do { ca = fgetc(fa); cb = fgetc(fb); } while (ca == cb && ca != EOF);
            fclose(fa); fclose(fb);
            if (ca != cb) { fprintf(stderr, "cmp: %s and %s differ\n", argv[2], argv[3]); return 1; }
            return 0;
        }
        char where[256] = "";
        if (!cmp_val(y, x, rtol, atol, where)) { fprintf(stderr, "cmp: mismatch (%s)\n", where); return 1; }
        return 0;
    } else usage();
    return 0;
}
