/* SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-SnapKitty-Opaque-1.0
 * Copyright (C) 2026 Ahmad Ali Parr / SnapKitty Research Lab
 */
/* Self-contained SHA-256 (FIPS 180-4). No external dependencies. */
#ifndef RO_SHA256_H
#define RO_SHA256_H

#include <stddef.h>
#include <stdint.h>

#define RO_SHA256_DIGEST_LEN 32u

typedef struct {
    uint32_t state[8];
    uint64_t total_len;   /* bytes absorbed so far */
    uint8_t  block[64];
    size_t   block_len;
} ro_sha256_ctx;

void ro_sha256_init(ro_sha256_ctx *ctx);
void ro_sha256_update(ro_sha256_ctx *ctx, const void *data, size_t len);
void ro_sha256_final(ro_sha256_ctx *ctx, uint8_t out[32]);
void ro_sha256(const void *data, size_t len, uint8_t out[32]);

/* Writes 64 lowercase hex characters plus a NUL terminator. */
void ro_hex32(const uint8_t digest[32], char out[65]);

#endif /* RO_SHA256_H */
