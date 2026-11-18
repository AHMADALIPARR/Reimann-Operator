/* SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-SnapKitty-Opaque-1.0
 * Copyright (C) 2026 Ahmad Ali Parr / SnapKitty Research Lab
 */
/* Minimal JSON reader and a writer that matches Python's json.dumps byte-for-byte:
 * float repr (shortest round-trip, Python exponent rules), NaN/Infinity, ensure_ascii,
 * sort_keys, and either compact (",", ":") or default (", ", ": ") separators. */
#ifndef RO_JSON_H
#define RO_JSON_H

#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

typedef enum { RJ_NULL, RJ_BOOL, RJ_INT, RJ_FLOAT, RJ_STR, RJ_ARR, RJ_OBJ } rj_type;

typedef struct rj_val rj_val;
struct rj_val {
    rj_type type;
    bool b;
    int64_t i;
    double d;
    char *s;          /* UTF-8, NUL terminated (strings and object keys) */
    size_t n;         /* array / object length */
    rj_val *items;    /* array items or object values */
    char **keys;      /* object keys */
};

rj_val *rj_parse(const char *text, char *err, size_t errlen);
rj_val *rj_parse_file(const char *path, char *err, size_t errlen);
void rj_free(rj_val *v);
const rj_val *rj_get(const rj_val *obj, const char *key);
double rj_num(const rj_val *v);

/* Growable output buffer. */
typedef struct { char *p; size_t len, cap; } rj_buf;
void rb_putc(rj_buf *b, char c);
void rb_puts(rj_buf *b, const char *s);
void rb_printf(rj_buf *b, const char *fmt, ...);
void rb_free(rj_buf *b);

/* Python repr(float) (nan/inf spelled as json.dumps spells them when json=true). */
void py_float_repr(double x, char out[40], bool json);
void rb_float(rj_buf *b, double x);
void rb_jstr(rj_buf *b, const char *utf8);       /* json.dumps(str) with ensure_ascii */
void rb_pystr(rj_buf *b, const char *s);         /* Python repr(str) for ASCII text */
void rb_value(rj_buf *b, const rj_val *v, bool sort_keys, bool compact);

#endif
