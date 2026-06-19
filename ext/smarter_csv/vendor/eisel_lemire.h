/* Eisel-Lemire decimal->double, ported from fast_float:
 * include/fast_float/decimal_to_binary.h, the compute_float<binary_format<double>>
 * + compute_product_approximation routines.
 *
 * Algorithm authors: Michael Eisel (original approach) and Daniel Lemire
 * (formalization, proof, and the fast_float implementation) — hence "Eisel-Lemire".
 *
 * Copyright (c) 2021 The fast_float authors. Tri-licensed Apache-2.0 / MIT / BSL-1.0;
 * used here under MIT — see LICENSE-fast_float-MIT in this directory.
 *
 * This is the "without fallback" variant (Noble Mushtak & Daniel Lemire, "Fast
 * Number Parsing Without Fallback"): for ANY nonzero mantissa w that fits exactly
 * in a uint64 (i.e. <= 19 significant digits, not truncated) and decimal exponent
 * q, it returns the correctly-rounded binary64 with no slow-path needed.
 *
 * smarter_json uses it as THE decimal->double path for mantissas up to 18 digits
 * (everything wider / overflowed / with an extreme exponent goes to the strtod
 * round-to-odd fallback). It is correctly-rounded across that whole range, with no
 * round-to-even tie loss, and is fast on the common short-mantissa case.
 * Verified bit-for-bit vs JSON.parse. See eisel_lemire.md for provenance. */
#ifndef FJ_EISEL_LEMIRE_H
#define FJ_EISEL_LEMIRE_H

#include <stdint.h>
#include <string.h>
#include "eisel_lemire_powers.h"

/* binary_format<double> constants from fast_float. */
#define FJ_EL_MANTISSA_BITS   52
#define FJ_EL_MIN_EXPONENT   (-1023)
#define FJ_EL_INFINITE_POWER  0x7FF
#define FJ_EL_SMALLEST_POW10 (-342)
#define FJ_EL_LARGEST_POW10   308
#define FJ_EL_MIN_RTE        (-4)   /* min_exponent_round_to_even */
#define FJ_EL_MAX_RTE         23    /* max_exponent_round_to_even */

/* (((152170 + 65536) * q) >> 16) + 63 == floor(log2(10^q)) + q + 63, see paper. */
static inline int32_t fj_el_power(int32_t q) {
  return (((152170 + 65536) * q) >> 16) + 63;
}

static inline void fj_el_mul128(uint64_t a, uint64_t b, uint64_t *hi, uint64_t *lo) {
#if defined(__SIZEOF_INT128__)
  __uint128_t p = (__uint128_t)a * (__uint128_t)b;
  *lo = (uint64_t)p;
  *hi = (uint64_t)(p >> 64);
#else
  uint64_t a0 = (uint32_t)a, a1 = a >> 32, b0 = (uint32_t)b, b1 = b >> 32;
  uint64_t p00 = a0 * b0, p01 = a0 * b1, p10 = a1 * b0, p11 = a1 * b1;
  uint64_t mid = p10 + (p00 >> 32) + (uint32_t)p01;
  *hi = p11 + (mid >> 32) + (p01 >> 32);
  *lo = (mid << 32) | (uint32_t)p00;
#endif
}

static inline double fj_el_bits2double(uint64_t bits) {
  double d;
  memcpy(&d, &bits, sizeof(d));
  return d;
}

/* q = power of ten, w = mantissa (NONZERO, exact, fits in uint64). neg = sign. */
static inline double fj_eisel_lemire_s2d(int64_t q, uint64_t w, int neg) {
  const uint64_t sign = (uint64_t)(neg != 0) << 63;
  uint64_t mantissa, prod_hi, prod_lo, sp_hi, sp_lo;
  int32_t  power2;
  int      lz, upperbit, shift, index;

  if (q < FJ_EL_SMALLEST_POW10) return fj_el_bits2double(sign); /* underflow -> 0 */
  if (q > FJ_EL_LARGEST_POW10)
    return fj_el_bits2double(sign | ((uint64_t)FJ_EL_INFINITE_POWER << FJ_EL_MANTISSA_BITS));

  lz = __builtin_clzll(w);
  w <<= lz;

  /* compute_product_approximation<mantissa_bits + 3 = 55>: precision_mask = 0x1FF. */
  index = 2 * (int)(q - FJ_EL_SMALLEST_POWER_OF_FIVE);
  fj_el_mul128(w, fj_power_of_five_128[index], &prod_hi, &prod_lo);
  if ((prod_hi & 0x1FF) == 0x1FF) {
    fj_el_mul128(w, fj_power_of_five_128[index + 1], &sp_hi, &sp_lo);
    prod_lo += sp_hi;
    if (sp_hi > prod_lo) prod_hi++;
  }

  upperbit = (int)(prod_hi >> 63);
  shift = upperbit + 64 - FJ_EL_MANTISSA_BITS - 3; /* upperbit + 9 */
  mantissa = prod_hi >> shift;
  power2 = (int32_t)(fj_el_power((int32_t)q) + upperbit - lz - FJ_EL_MIN_EXPONENT);

  if (power2 <= 0) { /* subnormal */
    if (-power2 + 1 >= 64) return fj_el_bits2double(sign); /* far below min -> 0 */
    mantissa >>= (-power2 + 1);
    mantissa += (mantissa & 1);
    mantissa >>= 1;
    power2 = (mantissa < ((uint64_t)1 << FJ_EL_MANTISSA_BITS)) ? 0 : 1;
    return fj_el_bits2double(sign | ((uint64_t)power2 << FJ_EL_MANTISSA_BITS) | mantissa);
  }

  /* round-to-even: if we land exactly between two doubles, round down. */
  if ((prod_lo <= 1) && (q >= FJ_EL_MIN_RTE) && (q <= FJ_EL_MAX_RTE) &&
      ((mantissa & 3) == 1) && ((mantissa << shift) == prod_hi)) {
    mantissa &= ~(uint64_t)1;
  }

  mantissa += (mantissa & 1);
  mantissa >>= 1;
  if (mantissa >= ((uint64_t)2 << FJ_EL_MANTISSA_BITS)) {
    mantissa = (uint64_t)1 << FJ_EL_MANTISSA_BITS;
    power2++;
  }
  mantissa &= ~((uint64_t)1 << FJ_EL_MANTISSA_BITS); /* drop implicit bit */
  if (power2 >= FJ_EL_INFINITE_POWER)
    return fj_el_bits2double(sign | ((uint64_t)FJ_EL_INFINITE_POWER << FJ_EL_MANTISSA_BITS));
  return fj_el_bits2double(sign | ((uint64_t)power2 << FJ_EL_MANTISSA_BITS) | mantissa);
}

#endif
