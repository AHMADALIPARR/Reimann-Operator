/* SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-SnapKitty-Opaque-1.0
 * Copyright (C) 2026 Ahmad Ali Parr / SnapKitty Research Lab
 */
#include "ro_json.h"

#include <math.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* ------------------------------------------------------------------ buffer */
static void rb_grow(rj_buf *b, size_t extra) {
    if (b->len + extra + 1 <= b->cap) return;
    size_t nc = b->cap ? b->cap : 256;
    while (nc < b->len + extra + 1) nc *= 2;
    char *np = realloc(b->p, nc);
    if (!np) { fputs("out of memory\n", stderr); exit(2); }
    b->p = np;
    b->cap = nc;
}
void rb_putc(rj_buf *b, char c) { rb_grow(b, 1); b->p[b->len++] = c; b->p[b->len] = 0; }
void rb_puts(rj_buf *b, const char *s) {
    size_t n = strlen(s);
    rb_grow(b, n);
    memcpy(b->p + b->len, s, n);
    b->len += n;
    b->p[b->len] = 0;
}
void rb_printf(rj_buf *b, const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    va_list ap2;
    va_copy(ap2, ap);
    int n = vsnprintf(NULL, 0, fmt, ap);
    va_end(ap);
    rb_grow(b, (size_t)n);
    vsnprintf(b->p + b->len, (size_t)n + 1, fmt, ap2);
    va_end(ap2);
    b->len += (size_t)n;
}
void rb_free(rj_buf *b) { free(b->p); b->p = NULL; b->len = b->cap = 0; }

/* ------------------------------------------------------------- float repr */
void py_float_repr(double x, char out[40], bool json) {
    if (isnan(x)) { strcpy(out, json ? "NaN" : "nan"); return; }
    if (isinf(x)) { strcpy(out, x > 0 ? (json ? "Infinity" : "inf") : (json ? "-Infinity" : "-inf")); return; }
    if (x == 0.0) { strcpy(out, signbit(x) ? "-0.0" : "0.0"); return; }
    char buf[48];
    int p;
    for (p = 1; p <= 17; ++p) {
        snprintf(buf, sizeof buf, "%.*e", p - 1, x);
        if (strtod(buf, NULL) == x) break;
    }
    /* buf = [-]d[.ddd]e[+-]XX */
    bool neg = buf[0] == '-';
    const char *m = buf + (neg ? 1 : 0);
    char digits[24];
    size_t nd = 0;
    const char *q = m;
    for (; *q && *q != 'e'; ++q)
        if (*q >= '0' && *q <= '9') digits[nd++] = *q;
    digits[nd] = 0;
    int e = atoi(q + 1);
    while (nd > 1 && digits[nd - 1] == '0') digits[--nd] = 0;
    char *o = out;
    if (neg) *o++ = '-';
    if (e < -4 || e >= 16) {
        *o++ = digits[0];
        if (nd > 1) { *o++ = '.'; memcpy(o, digits + 1, nd - 1); o += nd - 1; }
        o += sprintf(o, "e%c%02d", e < 0 ? '-' : '+', e < 0 ? -e : e);
    } else if (e < 0) {
        *o++ = '0'; *o++ = '.';
        for (int k = 0; k < -e - 1; ++k) *o++ = '0';
        memcpy(o, digits, nd); o += nd;
        *o = 0;
    } else {
        size_t intd = (size_t)e + 1;
        for (size_t k = 0; k < intd; ++k) *o++ = k < nd ? digits[k] : '0';
        *o++ = '.';
        if (nd > intd) { memcpy(o, digits + intd, nd - intd); o += nd - intd; }
        else *o++ = '0';
        *o = 0;
    }
}
void rb_float(rj_buf *b, double x) { char t[40]; py_float_repr(x, t, true); rb_puts(b, t); }

/* --------------------------------------------------------------- strings */
static uint32_t utf8_next(const unsigned char **pp) {
    const unsigned char *p = *pp;
    uint32_t c = *p++;
    if (c >= 0xF0) { c = ((c & 7u) << 18) | ((p[0] & 63u) << 12) | ((p[1] & 63u) << 6) | (p[2] & 63u); p += 3; }
    else if (c >= 0xE0) { c = ((c & 15u) << 12) | ((p[0] & 63u) << 6) | (p[1] & 63u); p += 2; }
    else if (c >= 0xC0) { c = ((c & 31u) << 6) | (p[0] & 63u); p += 1; }
    *pp = p;
    return c;
}
void rb_jstr(rj_buf *b, const char *s) {
    const unsigned char *p = (const unsigned char *)s;
    rb_putc(b, '"');
    while (*p) {
        uint32_t c = utf8_next(&p);
        switch (c) {
        case '"': rb_puts(b, "\\\""); break;
        case '\\': rb_puts(b, "\\\\"); break;
        case '\n': rb_puts(b, "\\n"); break;
        case '\r': rb_puts(b, "\\r"); break;
        case '\t': rb_puts(b, "\\t"); break;
        case '\b': rb_puts(b, "\\b"); break;
        case '\f': rb_puts(b, "\\f"); break;
        default:
            if (c < 0x20 || c > 0x7e) {
                if (c >= 0x10000) {
                    uint32_t v = c - 0x10000;
                    rb_printf(b, "\\u%04x\\u%04x", 0xD800u + (v >> 10), 0xDC00u + (v & 0x3FFu));
                } else rb_printf(b, "\\u%04x", c);
            } else rb_putc(b, (char)c);
        }
    }
    rb_putc(b, '"');
}
void rb_pystr(rj_buf *b, const char *s) {
    char q = strchr(s, '\'') && !strchr(s, '"') ? '"' : '\'';
    rb_putc(b, q);
    for (; *s; ++s) {
        if (*s == q || *s == '\\') rb_putc(b, '\\');
        rb_putc(b, *s);
    }
    rb_putc(b, q);
}

/* ---------------------------------------------------------------- parser */
typedef struct { const char *p; char *err; size_t errlen; int bad; } rj_ps;
static void ws(rj_ps *ps) { while (*ps->p == ' ' || *ps->p == '\t' || *ps->p == '\n' || *ps->p == '\r') ps->p++; }
static void fail(rj_ps *ps, const char *msg) { if (!ps->bad) snprintf(ps->err, ps->errlen, "JSON: %s", msg); ps->bad = 1; }
static void put_utf8(rj_buf *b, uint32_t c) {
    if (c < 0x80) rb_putc(b, (char)c);
    else if (c < 0x800) { rb_putc(b, (char)(0xC0 | (c >> 6))); rb_putc(b, (char)(0x80 | (c & 63))); }
    else if (c < 0x10000) { rb_putc(b, (char)(0xE0 | (c >> 12))); rb_putc(b, (char)(0x80 | ((c >> 6) & 63))); rb_putc(b, (char)(0x80 | (c & 63))); }
    else { rb_putc(b, (char)(0xF0 | (c >> 18))); rb_putc(b, (char)(0x80 | ((c >> 12) & 63))); rb_putc(b, (char)(0x80 | ((c >> 6) & 63))); rb_putc(b, (char)(0x80 | (c & 63))); }
}
static char *pstr(rj_ps *ps) {
    rj_buf b = {0};
    rb_puts(&b, "");
    ps->p++;
    while (*ps->p && *ps->p != '"') {
        if (*ps->p == '\\') {
            ps->p++;
            char c = *ps->p++;
            switch (c) {
            case 'n': rb_putc(&b, '\n'); break;
            case 't': rb_putc(&b, '\t'); break;
            case 'r': rb_putc(&b, '\r'); break;
            case 'b': rb_putc(&b, '\b'); break;
            case 'f': rb_putc(&b, '\f'); break;
            case 'u': {
                uint32_t u = (uint32_t)strtoul((char[]){ps->p[0], ps->p[1], ps->p[2], ps->p[3], 0}, NULL, 16);
                ps->p += 4;
                if (u >= 0xD800 && u < 0xDC00 && ps->p[0] == '\\' && ps->p[1] == 'u') {
                    uint32_t lo = (uint32_t)strtoul((char[]){ps->p[2], ps->p[3], ps->p[4], ps->p[5], 0}, NULL, 16);
                    ps->p += 6;
                    u = 0x10000 + ((u - 0xD800) << 10) + (lo - 0xDC00);
                }
                put_utf8(&b, u);
                break;
            }
            default: rb_putc(&b, c);
            }
        } else rb_putc(&b, *ps->p++);
    }
    if (*ps->p != '"') fail(ps, "unterminated string");
    else ps->p++;
    return b.p;
}
static void pval(rj_ps *ps, rj_val *v);
static void pval(rj_ps *ps, rj_val *v) {
    memset(v, 0, sizeof *v);
    ws(ps);
    char c = *ps->p;
    if (c == '{' || c == '[') {
        bool obj = c == '{';
        v->type = obj ? RJ_OBJ : RJ_ARR;
        ps->p++;
        size_t cap = 0;
        ws(ps);
        if (*ps->p == (obj ? '}' : ']')) { ps->p++; return; }
        for (;;) {
            if (v->n == cap) {
                cap = cap ? cap * 2 : 8;
                v->items = realloc(v->items, cap * sizeof *v->items);
                if (obj) v->keys = realloc(v->keys, cap * sizeof *v->keys);
            }
            if (obj) {
                ws(ps);
                if (*ps->p != '"') { fail(ps, "expected key"); return; }
                v->keys[v->n] = pstr(ps);
                ws(ps);
                if (*ps->p != ':') { fail(ps, "expected ':'"); return; }
                ps->p++;
            }
            pval(ps, &v->items[v->n++]);
            if (ps->bad) return;
            ws(ps);
            if (*ps->p == ',') { ps->p++; continue; }
            if (*ps->p == (obj ? '}' : ']')) { ps->p++; return; }
            fail(ps, "expected ',' or close");
            return;
        }
    }
    if (c == '"') { v->type = RJ_STR; v->s = pstr(ps); return; }
    if (!strncmp(ps->p, "true", 4)) { v->type = RJ_BOOL; v->b = true; ps->p += 4; return; }
    if (!strncmp(ps->p, "false", 5)) { v->type = RJ_BOOL; ps->p += 5; return; }
    if (!strncmp(ps->p, "null", 4)) { v->type = RJ_NULL; ps->p += 4; return; }
    if (!strncmp(ps->p, "NaN", 3)) { v->type = RJ_FLOAT; v->d = NAN; ps->p += 3; return; }
    if (!strncmp(ps->p, "Infinity", 8)) { v->type = RJ_FLOAT; v->d = INFINITY; ps->p += 8; return; }
    if (!strncmp(ps->p, "-Infinity", 9)) { v->type = RJ_FLOAT; v->d = -INFINITY; ps->p += 9; return; }
    const char *st = ps->p;
    if (*ps->p == '-') ps->p++;
    bool isf = false;
    while ((*ps->p >= '0' && *ps->p <= '9') || *ps->p == '.' || *ps->p == 'e' || *ps->p == 'E' ||
           ((*ps->p == '+' || *ps->p == '-') && (ps->p[-1] == 'e' || ps->p[-1] == 'E'))) {
        if (*ps->p == '.' || *ps->p == 'e' || *ps->p == 'E') isf = true;
        ps->p++;
    }
    if (ps->p == st) { fail(ps, "unexpected character"); return; }
    char tmp[64];
    size_t n = (size_t)(ps->p - st);
    if (n >= sizeof tmp) n = sizeof tmp - 1;
    memcpy(tmp, st, n);
    tmp[n] = 0;
    if (isf) { v->type = RJ_FLOAT; v->d = strtod(tmp, NULL); }
    else { v->type = RJ_INT; v->i = strtoll(tmp, NULL, 10); v->d = (double)v->i; }
}
rj_val *rj_parse(const char *text, char *err, size_t errlen) {
    rj_ps ps = {text, err, errlen, 0};
    rj_val *v = calloc(1, sizeof *v);
    pval(&ps, v);
    if (ps.bad) { rj_free(v); return NULL; }
    return v;
}
rj_val *rj_parse_file(const char *path, char *err, size_t errlen) {
    FILE *f = fopen(path, "rb");
    if (!f) { snprintf(err, errlen, "cannot open %s", path); return NULL; }
    fseek(f, 0, SEEK_END);
    long n = ftell(f);
    fseek(f, 0, SEEK_SET);
    char *t = malloc((size_t)n + 1);
    size_t got = fread(t, 1, (size_t)n, f);
    t[got] = 0;
    fclose(f);
    rj_val *v = rj_parse(t, err, errlen);
    free(t);
    return v;
}
static void rj_clear(rj_val *v) {
    free(v->s);
    for (size_t k = 0; k < v->n; ++k) {
        rj_clear(&v->items[k]);
        if (v->keys) free(v->keys[k]);
    }
    free(v->items);
    free(v->keys);
}
void rj_free(rj_val *v) { if (v) { rj_clear(v); free(v); } }
const rj_val *rj_get(const rj_val *o, const char *key) {
    if (!o || o->type != RJ_OBJ) return NULL;
    for (size_t k = 0; k < o->n; ++k)
        if (!strcmp(o->keys[k], key)) return &o->items[k];
    return NULL;
}
double rj_num(const rj_val *v) { return v ? (v->type == RJ_INT ? (double)v->i : v->d) : 0.0; }

/* ---------------------------------------------------------------- writer */
static int key_cmp_utf16(const char *a, const char *b) {
    /* Python sorts str keys by code point; UTF-8 byte order is the same order. */
    return strcmp(a, b);
}
void rb_value(rj_buf *b, const rj_val *v, bool sort_keys, bool compact) {
    const char *isep = compact ? "," : ", ";
    const char *ksep = compact ? ":" : ": ";
    switch (v->type) {
    case RJ_NULL: rb_puts(b, "null"); break;
    case RJ_BOOL: rb_puts(b, v->b ? "true" : "false"); break;
    case RJ_INT: rb_printf(b, "%lld", (long long)v->i); break;
    case RJ_FLOAT: rb_float(b, v->d); break;
    case RJ_STR: rb_jstr(b, v->s); break;
    case RJ_ARR:
        rb_putc(b, '[');
        for (size_t k = 0; k < v->n; ++k) {
            if (k) rb_puts(b, isep);
            rb_value(b, &v->items[k], sort_keys, compact);
        }
        rb_putc(b, ']');
        break;
    case RJ_OBJ: {
        size_t *ord = malloc((v->n + 1) * sizeof *ord);
        for (size_t k = 0; k < v->n; ++k) ord[k] = k;
        if (sort_keys)
            for (size_t i = 1; i < v->n; ++i)
                for (size_t j = i; j > 0 && key_cmp_utf16(v->keys[ord[j - 1]], v->keys[ord[j]]) > 0; --j) {
                    size_t t = ord[j]; ord[j] = ord[j - 1]; ord[j - 1] = t;
                }
        rb_putc(b, '{');
        for (size_t k = 0; k < v->n; ++k) {
            if (k) rb_puts(b, isep);
            rb_jstr(b, v->keys[ord[k]]);
            rb_puts(b, ksep);
            rb_value(b, &v->items[ord[k]], sort_keys, compact);
        }
        rb_putc(b, '}');
        free(ord);
        break;
    }
    }
}
