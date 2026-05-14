#include "ruby.h"
#include "ruby/encoding.h"
#include "ruby/version.h"
#include <stdio.h>
#include <stdbool.h>
#include <string.h>
#include <stdlib.h>
#include <errno.h>

#ifndef bool
  #define bool int
  #define false ((bool)0)
  #define true  ((bool)1)
#endif

/*
 * rb_hash_new_capa() was added in Ruby 3.2. For older Ruby versions,
 * we fall back to rb_hash_new() which doesn't pre-allocate capacity.
 */
#if defined(RUBY_API_VERSION_MAJOR) && (RUBY_API_VERSION_MAJOR > 3 || (RUBY_API_VERSION_MAJOR == 3 && RUBY_API_VERSION_MINOR >= 2))
  /* Ruby 3.2+ has rb_hash_new_capa */
#else
  #define rb_hash_new_capa(capa) rb_hash_new()
#endif

VALUE SmarterCSV = Qnil;
VALUE eMalformedCSVError = Qnil;
VALUE Parser = Qnil;

// Shared empty string to avoid allocating new empty strings for each empty CSV field.
// Empty fields are common in CSV files, and with strip_whitespace enabled (default),
// whitespace-only fields also become empty. Reusing a single frozen empty string
// significantly reduces object allocations and GC pressure.
VALUE Qempty_string = Qnil;

// Cached symbol IDs for fast options hash lookups (computed once at init)
static ID id_col_sep, id_quote_char, id_row_sep, id_missing_header_prefix;
static ID id_strip_whitespace, id_remove_empty_hashes, id_remove_empty_values;
static ID id_quote_escaping, id_convert_values_to_numeric, id_remove_zero_values;
static ID id_only, id_except, id_quote_boundary;
static ID id_only_headers, id_except_headers, id_keep_cols, id_strict;
static ID id_keep_bitmap, id_keep_extra_cols, id_early_exit_after_sym;
static ID id_backslash, id_standard;

/* ================================================================================
 * ParseContext — wraps all per-file parse options as a GC-managed TypedData object.
 *
 * Building a context once after headers are loaded eliminates the ~10 rb_hash_aref
 * calls that rb_parse_line_to_hash performs on every row.  The hot path calls
 * parse_line_to_hash_ctx_c(line, ctx) instead of parse_line_to_hash_c(line, headers, opts).
 * ================================================================================ */
typedef struct {
  /* Separator and quoting config — copied into C buffers, no Ruby GC tracking needed */
  char  col_sep_buf[8];
  int   col_sep_len;
  char  quote_char_val;
  char  row_sep_buf[16];
  int   row_sep_len;
  char  prefix_buf[64];
  const char *prefix_str;      /* "column_" literal or points into prefix_buf */

  /* Boolean parse flags */
  bool strip_ws;
  bool remove_empty;
  bool remove_empty_values;
  bool remove_zero_values;
  bool allow_escaped_quotes;   /* quote_escaping == :backslash */
  bool quote_boundary_standard;

  /* Numeric conversion: 0=off, 1=all, 2=only listed keys, 3=except listed keys */
  int  numeric_mode;

  /* Column filter bitmap (xmalloc'd; NULL when no filtering active) */
  bool *keep_bitmap;
  long  keep_bitmap_len;
  bool  keep_extra_columns;
  bool  has_only;
  long  early_exit_after;      /* column index after which we stop; -1 = no early exit */

  /* Hash allocation hint (set once at context creation) */
  long  hash_capa;

  /* GC-tracked Ruby values — must be marked in the mark callback */
  VALUE headers;
  VALUE numeric_keys;          /* Qnil when not used */
} parse_context_t;

__attribute__((cold)) static void parse_context_mark(void *ptr) {
  parse_context_t *ctx = (parse_context_t *)ptr;
#if defined(RUBY_API_VERSION_MAJOR) && (RUBY_API_VERSION_MAJOR > 2 || (RUBY_API_VERSION_MAJOR == 2 && RUBY_API_VERSION_MINOR >= 7))
  rb_gc_mark_movable(ctx->headers);
  rb_gc_mark_movable(ctx->numeric_keys);
#else
  rb_gc_mark(ctx->headers);
  if (!NIL_P(ctx->numeric_keys)) rb_gc_mark(ctx->numeric_keys);
#endif
}

#if defined(RUBY_API_VERSION_MAJOR) && (RUBY_API_VERSION_MAJOR > 2 || (RUBY_API_VERSION_MAJOR == 2 && RUBY_API_VERSION_MINOR >= 7))
__attribute__((cold)) static void parse_context_compact(void *ptr) {
  parse_context_t *ctx = (parse_context_t *)ptr;
  ctx->headers      = rb_gc_location(ctx->headers);
  ctx->numeric_keys = rb_gc_location(ctx->numeric_keys);
}
#endif

__attribute__((cold)) static void parse_context_free(void *ptr) {
  parse_context_t *ctx = (parse_context_t *)ptr;
  if (ctx->keep_bitmap) xfree(ctx->keep_bitmap);
  xfree(ctx);
}

__attribute__((cold)) static size_t parse_context_memsize(const void *ptr) {
  const parse_context_t *ctx = (const parse_context_t *)ptr;
  size_t sz = sizeof(parse_context_t);
  if (ctx->keep_bitmap) sz += (size_t)ctx->keep_bitmap_len * sizeof(bool);
  return sz;
}

static const rb_data_type_t parse_context_type = {
  "SmarterCSV::ParseContext",
  {
    parse_context_mark,
    parse_context_free,
    parse_context_memsize,
#if defined(RUBY_API_VERSION_MAJOR) && (RUBY_API_VERSION_MAJOR > 2 || (RUBY_API_VERSION_MAJOR == 2 && RUBY_API_VERSION_MINOR >= 7))
    parse_context_compact,
#else
    0,
#endif
  },
  0, 0,
  RUBY_TYPED_FREE_IMMEDIATELY | RUBY_TYPED_WB_PROTECTED
};

static VALUE unescape_quotes(char *str, long len, char quote_char, rb_encoding *encoding) {
  // Fast path: scan for any doubled quote pair. If none present, the field has
  // nothing to unescape — emit it directly via rb_enc_str_new and skip the
  // temp buffer + byte-by-byte copy. memchr is SIMD-optimized; the scan cost
  // is far less than the malloc/free pair this avoids.
  char *p = str;
  char *end = str + len;
  while ((p = memchr(p, quote_char, end - p))) {
    if (p + 1 < end && *(p + 1) == quote_char) goto needs_unescape;
    p++;
  }
  return rb_enc_str_new(str, len, encoding);

needs_unescape:
  // Slow path: at least one doubled quote pair was found. Allocate a temp
  // buffer and walk byte-by-byte, collapsing "" → ".
  {
    char *buf = ALLOC_N(char, len);
    long j = 0;
    for (long i = 0; i < len; i++) {
      if (str[i] == quote_char && i + 1 < len && str[i + 1] == quote_char) {
        buf[j++] = quote_char;
        i++; // skip second quote
      } else {
        buf[j++] = str[i];
      }
    }
    VALUE out = rb_enc_str_new(buf, j, encoding);
    xfree(buf);
    return out;
  }
}

/* Helper: build the 2-element [elements, data_size] tuple returned by rb_parse_csv_line.
 * Aligns this function's return shape with parse_csv_line_ruby and rb_parse_line_to_hash_ctx:
 * data_size = -1 signals "unclosed quoted field — needs more data". */
static inline VALUE make_parse_result(VALUE elements, long data_size) {
  VALUE result = rb_ary_new_capa(2);
  rb_ary_push(result, elements);
  rb_ary_push(result, LONG2FIX(data_size));
  return result;
}

static VALUE rb_parse_csv_line(VALUE self, VALUE line, VALUE col_sep, VALUE quote_char, VALUE max_size, VALUE has_quotes_val, VALUE strip_ws_val, VALUE allow_escaped_quotes_val, VALUE quote_boundary_standard_val, VALUE row_sep_val) {
  if (RB_TYPE_P(line, T_NIL) == 1) {
    return make_parse_result(rb_ary_new(), 0);
  }

  if (RB_TYPE_P(line, T_STRING) != 1) {
    rb_raise(rb_eTypeError, "ERROR in SmarterCSV.parse_line: line has to be a string or nil");
  }

  rb_encoding *encoding = rb_enc_get(line);
  char *startP = RSTRING_PTR(line);
  long line_len = RSTRING_LEN(line);
  char *endP = startP + line_len;
  char *p = startP;

  char *col_sepP = RSTRING_PTR(col_sep);
  long col_sep_len = RSTRING_LEN(col_sep);

  char *quoteP = RSTRING_PTR(quote_char);
  char quote_char_val = quoteP[0];

  VALUE elements = rb_ary_new();
  VALUE field;

  long element_count = 0;
  int max_fields = -1;
  if (max_size != Qnil) {
    max_fields = NUM2INT(max_size);
    if (max_fields < 0) {
      return make_parse_result(rb_ary_new(), 0);
    }
  }

  bool has_quotes = RTEST(has_quotes_val);
  bool strip_ws = RTEST(strip_ws_val);
  bool allow_escaped_quotes = RTEST(allow_escaped_quotes_val);
  bool quote_boundary_standard = RTEST(quote_boundary_standard_val);

  char *row_sepP = (RB_TYPE_P(row_sep_val, T_STRING)) ? RSTRING_PTR(row_sep_val) : NULL;
  long row_sep_len = (row_sepP) ? RSTRING_LEN(row_sep_val) : 0;

  // === FAST PATH: No quotes and single-character separator ===
  if (__builtin_expect(!has_quotes && col_sep_len == 1, 1)) {
    char sep = *col_sepP;
    char *sep_pos = NULL;

    while ((sep_pos = memchr(p, sep, endP - p))) {
      if ((max_fields >= 0) && (element_count >= max_fields)) {
        break;
      }

      long field_len = sep_pos - startP;
      char *raw_field = startP;
      char *trim_start = raw_field;
      char *trim_end = raw_field + field_len - 1;

      if (strip_ws) {
        while (trim_start <= trim_end && (*trim_start == ' ' || *trim_start == '\t')) trim_start++;
        while (trim_end >= trim_start && (*trim_end == ' ' || *trim_end == '\t')) trim_end--;
      }

      long trimmed_len = (trim_end >= trim_start) ? (trim_end - trim_start + 1) : 0;

      field = (trimmed_len > 0) ? rb_enc_str_new(trim_start, trimmed_len, encoding) : Qempty_string;
      rb_ary_push(elements, field);
      element_count++;

      p = sep_pos + 1;
      startP = p;
    }

    if ((max_fields < 0) || (element_count < max_fields)) {
      long field_len = endP - startP;
      char *raw_field = startP;
      char *trim_start = raw_field;
      char *trim_end = raw_field + field_len - 1;

      if (strip_ws) {
        while (trim_start <= trim_end && (*trim_start == ' ' || *trim_start == '\t')) trim_start++;
        while (trim_end >= trim_start && (*trim_end == ' ' || *trim_end == '\t')) trim_end--;
      }

      long trimmed_len = (trim_end >= trim_start) ? (trim_end - trim_start + 1) : 0;

      field = (trimmed_len > 0) ? rb_enc_str_new(trim_start, trimmed_len, encoding) : Qempty_string;
      rb_ary_push(elements, field);
    }

    return make_parse_result(elements, RARRAY_LEN(elements));
  }

  // === SLOW PATH: Quoted fields or multi-char separator ===
  long i;
  long backslash_count = 0;
  bool in_quotes = false;
  bool col_sep_found = true;
  bool field_started = false;  // for quote_boundary_standard: true once field has non-boundary content

  while (p < endP) {
    col_sep_found = true;
    for (i = 0; (i < col_sep_len) && (p + i < endP); i++) {
      if (*(p + i) != *(col_sepP + i)) {
        col_sep_found = false;
        break;
      }
    }

    if (col_sep_found && !in_quotes) {
      if ((max_fields >= 0) && (element_count >= max_fields)) {
        break;
      }

      long field_len = p - startP;
      char *raw_field = startP;

      bool quoted = (field_len >= 2 && raw_field[0] == quote_char_val && raw_field[field_len - 1] == quote_char_val);
      if (quoted) {
        raw_field++;
        field_len -= 2;
      }

      char *trim_start = raw_field;
      char *trim_end = raw_field + field_len - 1;

      if (strip_ws) {
        while (trim_start <= trim_end && (*trim_start == ' ' || *trim_start == '\t')) trim_start++;
        while (trim_end >= trim_start && (*trim_end == ' ' || *trim_end == '\t')) trim_end--;
      }

      long trimmed_len = (trim_end >= trim_start) ? (trim_end - trim_start + 1) : 0;

      if (trimmed_len == 0) {
        field = Qempty_string;
      } else if (quoted || memchr(trim_start, quote_char_val, trimmed_len)) {
        field = unescape_quotes(trim_start, trimmed_len, quote_char_val, encoding);
      } else {
        field = rb_enc_str_new(trim_start, trimmed_len, encoding);
      }

      rb_ary_push(elements, field);
      element_count++;

      p += col_sep_len;
      startP = p;
      backslash_count = 0;
      field_started = false;  // reset for next field
    } else {
      if (allow_escaped_quotes && *p == '\\') {
        backslash_count++;
        if (__builtin_expect(quote_boundary_standard, 1) && !in_quotes) field_started = true;
      } else {
        if (*p == quote_char_val) {
          if (!allow_escaped_quotes || backslash_count % 2 == 0) {
            if (__builtin_expect(quote_boundary_standard, 1)) {
              if (in_quotes) {
                // closing quote: only valid if followed by col_sep, row_sep, or end of line
                bool valid_close = (p + 1 >= endP);
                if (!valid_close) {
                  valid_close = true;
                  for (long j = 0; j < col_sep_len; j++) {
                    if (*(p + 1 + j) != *(col_sepP + j)) { valid_close = false; break; }
                  }
                }
                if (!valid_close && row_sep_len > 0) {
                  valid_close = true;
                  for (long j = 0; j < row_sep_len; j++) {
                    if (*(p + 1 + j) != *(row_sepP + j)) { valid_close = false; break; }
                  }
                }
                if (valid_close) {
                  in_quotes = false;
                  field_started = true;
                }
                // else: quote inside quoted field → literal (handles "" doubling)
              } else if (!field_started) {
                in_quotes = true;     // opening quote at field boundary
                field_started = true;
              }
              // else: mid-field quote → treat as literal
            } else {
              in_quotes = !in_quotes;
            }
          }
        } else if (__builtin_expect(quote_boundary_standard, 1) && !in_quotes) {
          if (strip_ws) {
            if (*p != ' ' && *p != '\t') {
              field_started = true;
            } else if (!field_started) {
              startP = p + 1; /* advance past leading whitespace so quote-detection at extraction sees the quote */
            }
          } else {
            field_started = true;
          }
        }
        backslash_count = 0;
      }
      p++;
    }
  }

  if (in_quotes) {
    /* Unclosed quoted field at EOL: signal "needs more data" rather than raising.
     * Aligns with parse_csv_line_ruby and rb_parse_line_to_hash_ctx, which both
     * return data_size = -1 on this condition. The Reader's stitch loop consumes
     * the signal: append the next physical line and re-parse, or raise MalformedCSV
     * at EOF if the field never closes. The parser does not decide "ultimately
     * malformed"; the caller does. */
    return make_parse_result(rb_ary_new(), -1);
  }

  if ((max_fields < 0) || (element_count < max_fields)) {
    long field_len = endP - startP;
    char *raw_field = startP;

    bool quoted = (field_len >= 2 && raw_field[0] == quote_char_val && raw_field[field_len - 1] == quote_char_val);
    if (quoted) {
      raw_field++;
      field_len -= 2;
    }

    char *trim_start = raw_field;
    char *trim_end = raw_field + field_len - 1;

    if (strip_ws) {
      while (trim_start <= trim_end && (*trim_start == ' ' || *trim_start == '\t')) trim_start++;
      while (trim_end >= trim_start && (*trim_end == ' ' || *trim_end == '\t')) trim_end--;
    }

    long trimmed_len = (trim_end >= trim_start) ? (trim_end - trim_start + 1) : 0;

    if (trimmed_len == 0) {
      field = Qempty_string;
    } else if (quoted || memchr(trim_start, quote_char_val, trimmed_len)) {
      field = unescape_quotes(trim_start, trimmed_len, quote_char_val, encoding);
    } else {
      field = rb_enc_str_new(trim_start, trimmed_len, encoding);
    }

    rb_ary_push(elements, field);
  }

  return make_parse_result(elements, RARRAY_LEN(elements));
}

// Efficiently combine two arrays into a hash (replaces headers.zip(values).to_h)
// This eliminates the intermediate array allocation from zip and the to_h conversion.
// For CSV files with many columns, this significantly reduces object allocations.
// Matches Ruby's zip behavior: pads with nil when values array is shorter than keys.
static VALUE rb_zip_to_hash(VALUE self, VALUE keys, VALUE values) {
  if (NIL_P(keys) || NIL_P(values)) return rb_hash_new();

  long keys_len = RARRAY_LEN(keys);
  long vals_len = RARRAY_LEN(values);

  VALUE hash = rb_hash_new_capa(keys_len);
  for (long i = 0; i < keys_len; i++) {
    VALUE val = (i < vals_len) ? rb_ary_entry(values, i) : Qnil;
    rb_hash_aset(hash, rb_ary_entry(keys, i), val);
  }
  return hash;
}

/*
 * ================================================================================
 * get_key_for_index - Helper to get the hash key for a given column index
 * ================================================================================
 *
 * For columns within the headers array, returns the corresponding header symbol.
 * For extra columns (beyond headers), generates a symbol like :column_7, :column_8, etc.
 *
 * This supports CSV files where some rows have more columns than the header row.
 */
static inline VALUE get_key_for_index(long index, VALUE headers, long headers_len, const char *prefix_str) {
  if (index < headers_len) {
    // Use existing header from the headers array
    return rb_ary_entry(headers, index);
  } else {
    // Generate a new key for extra columns: "column_7" -> :column_7
    char key_buf[64];
    snprintf(key_buf, sizeof(key_buf), "%s%ld", prefix_str, index + 1);
    return ID2SYM(rb_intern(key_buf));
  }
}

/*
 * ================================================================================
 * try_numeric_conversion - Attempt to convert a raw C string to integer or float
 * ================================================================================
 *
 * Tries to parse the trimmed field as an integer (strtol) or float (strtod).
 * Returns the converted Ruby numeric value, or Qundef if the field is not numeric.
 *
 * This avoids creating a Ruby String object for fields that will become numbers,
 * eliminating both the string allocation and the later regex + to_i/to_f in Ruby.
 *
 * Handles overflow: if strtol overflows (ERANGE), falls back to rb_cstr_to_inum
 * which produces a Ruby Bignum.
 */
static inline VALUE try_numeric_conversion(char *trim_start, long trimmed_len) {
  // Quick pre-check: first char must be digit, +, -, or .
  char first = trim_start[0];
  if (!((first >= '0' && first <= '9') || first == '+' || first == '-' || first == '.')) {
    return Qundef;
  }

  // Need null-terminated string for strtol/strtod; use stack buffer for typical fields
  if (trimmed_len >= 63) return Qundef;  // very long fields are unlikely to be simple numbers

  char num_buf[64];
  memcpy(num_buf, trim_start, trimmed_len);
  num_buf[trimmed_len] = '\0';

  char *endptr;

  // Try integer first (most common numeric type in CSV)
  // Don't try integer if field starts with '.' (e.g., ".5")
  if (first != '.') {
    errno = 0;
    long int_val = strtol(num_buf, &endptr, 10);
    if (endptr == num_buf + trimmed_len) {
      // Entire string was consumed → valid integer
      if (errno == ERANGE) {
        // Overflow: fall back to Ruby Bignum
        return rb_cstr_to_inum(num_buf, 10, false);
      }
      return LONG2NUM(int_val);
    }
  }

  // Try float (only if contains '.')
  if (memchr(num_buf, '.', trimmed_len)) {
    errno = 0;
    double float_val = strtod(num_buf, &endptr);
    if (endptr == num_buf + trimmed_len && errno != ERANGE) {
      return DBL2NUM(float_val);
    }
  }

  return Qundef;  // not numeric
}

/*
 * leading_whitespace_len - byte length (1, 2, or 3) of the whitespace character at the start of
 * `s` (with `len` bytes available), or 0 if `s` does not start with whitespace.
 *
 * "Whitespace" here matches Ruby's [[:space:]] / Rails' String#blank? — the Unicode White_Space
 * set — so the C blank check stays consistent with the Ruby fallback path (hash_transformations).
 * ASCII bytes are handled with a single comparison; the multibyte arms are only reached when a
 * byte >= 0x80 appears, so all-ASCII fields pay nothing extra.
 */
static inline int leading_whitespace_len(const char *s, long len) {
  if (len < 1) return 0;
  unsigned char b0 = (unsigned char)s[0];
  if (b0 == 0x20 || (b0 >= 0x09 && b0 <= 0x0D)) return 1;  // space (most common) then \t \n \v \f \r
  if (b0 < 0x80) return 0;                                 // any other ASCII byte: not whitespace
  if (len < 2) return 0;
  unsigned char b1 = (unsigned char)s[1];
  if (b0 == 0xC2 && (b1 == 0x85 || b1 == 0xA0)) return 2;  // U+0085 NEL, U+00A0 NBSP
  if (len < 3) return 0;
  unsigned char b2 = (unsigned char)s[2];
  if (b0 == 0xE1 && b1 == 0x9A && b2 == 0x80) return 3;    // U+1680 OGHAM SPACE MARK
  if (b0 == 0xE2) {
    // U+2000..U+200A (E2 80 80..8A) — note: 0x8B is U+200B ZERO WIDTH SPACE, NOT whitespace.
    // U+2028 LINE SEP (A8), U+2029 PARA SEP (A9), U+202F NARROW NBSP (AF), U+205F MMSP (E2 81 9F).
    if (b1 == 0x80 && ((b2 >= 0x80 && b2 <= 0x8A) || b2 == 0xA8 || b2 == 0xA9 || b2 == 0xAF)) return 3;
    if (b1 == 0x81 && b2 == 0x9F) return 3;
    return 0;
  }
  if (b0 == 0xE3 && b1 == 0x80 && b2 == 0x80) return 3;    // U+3000 IDEOGRAPHIC SPACE
  return 0;
}

/*
 * ================================================================================
 * Transformation options struct - passed to insert_field_into_hash to avoid
 * repeating 10+ parameters at each of the 4 field-insertion call sites.
 * ================================================================================
 */
typedef struct {
  VALUE hash;               // Lazily allocated: starts as Qnil, allocated on first insert
  VALUE headers;
  VALUE numeric_keys;
  rb_encoding *encoding;
  const char *prefix_str;
  long headers_len;
  long hash_capa;           // Pre-computed capacity for lazy hash allocation
  int numeric_mode;         // 0=off, 1=all, 2=only, 3=except
  bool remove_empty_values;
  bool remove_zero_values;
} field_transform_opts;

/*
 * ensure_hash_allocated - Lazily allocate the hash on first field insertion.
 * Avoids rb_hash_new_capa + GC registration for rows that are entirely blank
 * or filtered out (all values removed by transforms).
 */
static inline void ensure_hash_allocated(field_transform_opts *opts) {
  if (__builtin_expect(NIL_P(opts->hash), 0)) {
    opts->hash = rb_hash_new_capa(opts->hash_capa);
  }
}

/*
 * ================================================================================
 * insert_field_into_hash - Process a single parsed field and insert into hash
 * ================================================================================
 *
 * Applies the full transformation pipeline to a single field:
 *   1. Skip empty/blank fields (when remove_empty_values is true)
 *   2. Skip zero values via string scan (when remove_zero_values is true)
 *      Works independently of numeric conversion — matches /\A0+(?:\.0+)?\z/
 *   3. Try numeric conversion (strtol/strtod) — avoids Ruby String allocation
 *   4. Insert the final value into the hash as String
 *
 * For quoted fields, pass is_quoted=true — numeric conversion is skipped since
 * the raw C string may differ from the unescaped content.
 *
 * Returns: true if a non-blank value was inserted, false otherwise.
 *          (Used to track all_blank for remove_empty_hashes.)
 */
static inline __attribute__((always_inline)) bool insert_field_into_hash(
    field_transform_opts *opts,
    char *trim_start, long trimmed_len,
    long element_count, bool is_quoted,
    char quote_char_val, rb_encoding *encoding
) {
  VALUE key = get_key_for_index(element_count, opts->headers, opts->headers_len, opts->prefix_str);

  // 1. Empty/blank field handling
  // A field is blank if it is zero-length or consists entirely of whitespace characters.
  // "Whitespace" matches Ruby's BLANK_RE = /\A[[:space:]]*\z/ (and Rails' String#blank?) — the
  // Unicode White_Space set — so this stays consistent with the Ruby fallback path.
  if (opts->remove_empty_values) {
    bool is_blank = true;
    long i = 0;
    while (i < trimmed_len) {
      int w = leading_whitespace_len(trim_start + i, trimmed_len - i);
      if (w == 0) { is_blank = false; break; }
      i += w;
    }
    if (is_blank) return false;  // skip blank value
  }

  if (trimmed_len == 0) {
    ensure_hash_allocated(opts);
    rb_hash_aset(opts->hash, key, Qempty_string);
    return false;  // not a non-blank value
  }

  // 2. String-based zero check — matches /\A[+-]?0+(?:\.0+)?\z/
  // Works independently of numeric conversion: "0", "00", "0.0", "00.00", "+0", "-0.00" etc.
  // Outer quotes are stripped before this call, so the check applies equally
  // to quoted ("0") and unquoted (0) fields.
  if (opts->remove_zero_values) {
    char c0 = trim_start[0];  // trimmed_len > 0 guaranteed (zero-length handled above)
    // Index i skips an optional leading sign; bail right away if the first byte can't begin a zero.
    long i = (c0 == '0') ? 0
           : (c0 == '+' || c0 == '-') ? 1
           : trimmed_len;
    if (i < trimmed_len && trim_start[i] == '0') {
      while (i < trimmed_len && trim_start[i] == '0') i++;
      if (i == trimmed_len) return false;  // all zeros, e.g. "0", "00", "+0", "-00"
      if (trim_start[i] == '.') {
        i++;
        long dot_pos = i;
        while (i < trimmed_len && trim_start[i] == '0') i++;
        // Valid if we consumed everything AND had at least one zero after dot
        if (i == trimmed_len && i > dot_pos) return false;  // e.g. "0.0", "00.00", "+0.0", "-0.00"
      }
    }
  }

  // 4. Try numeric conversion before creating a Ruby string
  if (opts->numeric_mode > 0) {
    bool do_convert = (opts->numeric_mode == 1) ||
                      (opts->numeric_mode == 2 && rb_ary_includes(opts->numeric_keys, key) == Qtrue) ||
                      (opts->numeric_mode == 3 && rb_ary_includes(opts->numeric_keys, key) != Qtrue);
    if (do_convert) {
      VALUE numeric = try_numeric_conversion(trim_start, trimmed_len);
      if (numeric != Qundef) {
        ensure_hash_allocated(opts);
        rb_hash_aset(opts->hash, key, numeric);
        return true;
      }
    }
  }

  // 5. Not numeric: insert as string.
  // Use unescape_quotes for quoted fields to handle embedded doubled quotes ("" → ").
  // For simple quoted fields like "hello" with no embedded quotes, unescape_quotes
  // returns the content unchanged (just like rb_enc_str_new would).
  VALUE field = is_quoted
    ? unescape_quotes(trim_start, trimmed_len, quote_char_val, encoding)
    : rb_enc_str_new(trim_start, trimmed_len, encoding);
  ensure_hash_allocated(opts);
  rb_hash_aset(opts->hash, key, field);
  return true;
}

/*
 * ================================================================================
 * rb_parse_line_to_hash - Parse CSV line directly into a Ruby Hash
 * ================================================================================
 *
 * This is the main parsing function that converts a CSV line directly into a hash.
 * It builds the hash during parsing to avoid intermediate array allocations.
 *
 * PERFORMANCE NOTES:
 * -----------------
 * - Builds hash directly during parsing (no intermediate values array)
 * - Uses a fast path for the common case (no quotes, single-char separator)
 * - Reuses a shared empty string (Qempty_string) to reduce allocations
 * - Tracks blank fields to support remove_empty_hashes option
 *
 * PARAMETERS:
 * -----------
 * @param line           - The CSV line to parse (Ruby String)
 * @param headers        - Array of header symbols for hash keys
 * @param col_sep        - Column separator string (e.g., ",")
 * @param quote_char     - Quote character string (e.g., "\"")
 * @param header_prefix  - Prefix for auto-generated column names (e.g., "column_")
 * @param has_quotes_val - Boolean: whether line contains quote characters (optimization hint)
 * @param strip_ws_val   - Boolean: whether to strip whitespace from field values
 * @param remove_empty_val - Boolean: if true, return nil for rows where all values are blank
 * @param remove_empty_values_val - Boolean: if true, don't add nil for missing columns
 *                                  (they'd be removed anyway by hash_transformations)
 *
 * RETURNS:
 * --------
 * A Ruby Array [hash, data_size] where:
 *   - hash is the parsed row as a Hash, or nil if all values were blank (and remove_empty_val is true)
 *   - data_size is the number of fields parsed (used to detect extra columns)
 *
 * EXAMPLE:
 * --------
 * Input:  line = "john,25,boston", headers = [:name, :age, :city]
 * Output: [{name: "john", age: "25", city: "boston"}, 3]
 *
 * Input:  line = "john,25,boston,extra" (more fields than headers)
 * Output: [{name: "john", age: "25", city: "boston", column_4: "extra"}, 4]
 */
__attribute__((hot)) static VALUE rb_parse_line_to_hash(VALUE self, VALUE line, VALUE headers, VALUE options_hash) {

  /* ----------------------------------------
   * SECTION 1: Handle nil/invalid input
   * ---------------------------------------- */
  if (NIL_P(line)) {
    VALUE result = rb_ary_new_capa(2);
    rb_ary_push(result, Qnil);
    rb_ary_push(result, INT2FIX(0));
    return result;
  }

  if (RB_TYPE_P(line, T_STRING) != 1) {
    rb_raise(rb_eTypeError, "ERROR in SmarterCSV.parse_line_to_hash: line has to be a string or nil");
  }

  /* ----------------------------------------
   * SECTION 2: Extract options from hash and convert to C types
   * ----------------------------------------
   * Options are extracted once per line using cached symbol IDs
   * for fast hash lookups (symbol comparison is pointer equality).
   */
  VALUE col_sep = rb_hash_aref(options_hash, ID2SYM(id_col_sep));
  VALUE quote_char = rb_hash_aref(options_hash, ID2SYM(id_quote_char));
  VALUE header_prefix = rb_hash_aref(options_hash, ID2SYM(id_missing_header_prefix));
  bool strip_ws = RTEST(rb_hash_aref(options_hash, ID2SYM(id_strip_whitespace)));
  bool remove_empty = RTEST(rb_hash_aref(options_hash, ID2SYM(id_remove_empty_hashes)));
  bool remove_empty_values = RTEST(rb_hash_aref(options_hash, ID2SYM(id_remove_empty_values)));
  bool remove_zero_values = RTEST(rb_hash_aref(options_hash, ID2SYM(id_remove_zero_values)));

  // Numeric conversion: supports true (all), {only: [...]}, {except: [...]}
  // numeric_mode: 0=off, 1=all, 2=only listed keys, 3=except listed keys
  int numeric_mode = 0;
  VALUE numeric_keys = Qnil;
  VALUE convert_opt = rb_hash_aref(options_hash, ID2SYM(id_convert_values_to_numeric));
  if (RTEST(convert_opt)) {
    if (RB_TYPE_P(convert_opt, T_HASH)) {
      VALUE only_keys = rb_hash_aref(convert_opt, ID2SYM(id_only));
      VALUE except_keys = rb_hash_aref(convert_opt, ID2SYM(id_except));
      if (RTEST(only_keys)) {
        numeric_mode = 2;
        numeric_keys = rb_Array(only_keys);   // wrap single value in array if needed
      } else if (RTEST(except_keys)) {
        numeric_mode = 3;
        numeric_keys = rb_Array(except_keys); // wrap single value in array if needed
      }
    } else {
      numeric_mode = 1;  // convert all
    }
  }

  // quote_escaping and quote_boundary are only needed in Section 5 (quoted/slow path).
  // They are declared here as forward declarations so Section 5 can set them lazily.
  bool allow_escaped_quotes = false;   // set in Section 5 on first entry
  bool quote_boundary_standard = false; // set in Section 5 on first entry

  rb_encoding *encoding = rb_enc_get(line);      // Preserve string encoding
  char *startP = RSTRING_PTR(line);              // Pointer to start of current field
  long line_len = RSTRING_LEN(line);
  char *endP = startP + line_len;                // End of line marker
  char *p = startP;                              // Current parsing position

  // Chomp: strip trailing row separator (pointer adjustment, no string mutation).
  // row_sep is also reused in Section 5 for the closing-quote boundary check.
  VALUE row_sep = rb_hash_aref(options_hash, ID2SYM(id_row_sep));
  if (!NIL_P(row_sep) && RB_TYPE_P(row_sep, T_STRING)) {
    char *row_sepP = RSTRING_PTR(row_sep);
    long row_sep_len = RSTRING_LEN(row_sep);
    if (line_len >= row_sep_len && memcmp(endP - row_sep_len, row_sepP, row_sep_len) == 0) {
      endP -= row_sep_len;
    }
  }

  char *col_sepP = RSTRING_PTR(col_sep);
  long col_sep_len = RSTRING_LEN(col_sep);

  char *quoteP = RSTRING_PTR(quote_char);
  char quote_char_val = quoteP[0];               // First char of quote string

  // Default prefix for extra columns is "column_" (e.g., :column_7)
  const char *prefix_str = NIL_P(header_prefix) ? "column_" : RSTRING_PTR(header_prefix);

  long headers_len = NIL_P(headers) ? 0 : RARRAY_LEN(headers);
  // Optimization hint: check if line contains quote characters
  bool has_quotes = (memchr(startP, quote_char_val, line_len) != NULL);

  /* ----------------------------------------
   * Column-filter bitmap for only_headers: / except_headers:
   * ----------------------------------------
   * keep_bitmap[i] = true  → include column i in the output hash
   * keep_bitmap[i] = false → skip column i (no Ruby allocation at all)
   * NULL when no filter is active — zero overhead on common path.
   *
   * Preferred source: options[:_keep_cols] — a Ruby Array of true/false values
   * precomputed once in reader.rb after headers are loaded (O(1) Set lookups).
   * Copying it here is O(headers_len) with O(1) per element — no rb_ary_includes.
   *
   * Fallback: build from only_headers/except_headers via rb_ary_includes (O(k)
   * per column, k = filter list length). Used only when _keep_cols is absent.
   *
   * Capped at 4096 columns; wider CSVs fall back to the Ruby-side
   * hash.select!/hash.reject! filter applied after return.
   *
   * The bitmap is a loop invariant: headers and filter settings never change between rows.
   * reader.rb precomputes it once as a packed binary String (_keep_bitmap) and also
   * pre-stores keep_extra_cols and early_exit_after, so C just does 3 hash lookups +
   * one memcpy instead of N rb_ary_entry calls on every row.
   *
   * alloca() keeps the allocation conditional: no-filter path never calls alloca(), so
   * the frame stays well below 4 KB and ___chkstk_darwin never fires on ARM64 macOS.
   */
  bool *keep_bitmap = NULL;
  bool keep_extra_columns = true; /* extra cols (> headers_len): keep by default */
  bool has_only = false;          /* true when only_headers: filtering is active */
  long early_exit_after = -1;     /* column index after which we stop; -1 = no early exit */

  /* Column-filter bitmap setup.
   *
   * _keep_cols is the gate key — checked with a single rb_hash_aref on every row:
   *   false (default) → no filtering; skip everything instantly.  ← COMMON CASE, zero overhead
   *   nil             → filter active (reader.rb path): check _keep_bitmap for the fast bitmap.
   *   Array           → backward-compat: direct C API callers passing _keep_cols as an Array.
   *
   * When _keep_cols is absent from the hash (nil from rb_hash_aref), it falls through to
   * deriving the bitmap from only_headers/except_headers directly (manual options hashes).
   *
   * only_headers: / except_headers: are RARELY used options.  The common path (no filtering)
   * pays exactly one rb_hash_aref and nothing else.
   */
  VALUE keep_cols_val = rb_hash_aref(options_hash, ID2SYM(id_keep_cols));
  if (keep_cols_val != Qfalse) {
    /* Not false: either nil (filter active / absent) or Array (backward-compat). */
    if (NIL_P(keep_cols_val)) {
      /* nil: reader.rb filter path — check _keep_bitmap, or fall back to deriving it. */
      VALUE prebuilt_bitmap = rb_hash_aref(options_hash, ID2SYM(id_keep_bitmap));
      if (RB_TYPE_P(prebuilt_bitmap, T_STRING)
          && headers_len > 0 && RSTRING_LEN(prebuilt_bitmap) >= headers_len) {
        /* Precomputed binary bitmap from reader.rb — one memcpy replaces N rb_ary_entry calls.
         * Copy before any Ruby API calls that could trigger GC compaction. */
        keep_bitmap = (bool *)alloca((size_t)headers_len * sizeof(bool));
        memcpy(keep_bitmap, RSTRING_PTR(prebuilt_bitmap), (size_t)headers_len * sizeof(bool));
        VALUE kec = rb_hash_aref(options_hash, ID2SYM(id_keep_extra_cols));
        keep_extra_columns = NIL_P(kec) ? true : RTEST(kec);
        VALUE exa = rb_hash_aref(options_hash, ID2SYM(id_early_exit_after_sym));
        early_exit_after = RB_INTEGER_TYPE_P(exa) ? NUM2LONG(exa) : -1;
        has_only = !keep_extra_columns;
      } else if (headers_len > 0 && headers_len <= 4096) {
        /* Last resort: derive from only_headers/except_headers directly.
         * Only reached when options hash is built manually without any _keep_* keys. */
        VALUE only_hdrs  = rb_hash_aref(options_hash, ID2SYM(id_only_headers));
        VALUE except_hdrs = rb_hash_aref(options_hash, ID2SYM(id_except_headers));
        bool has_except  = RB_TYPE_P(except_hdrs, T_ARRAY) && RARRAY_LEN(except_hdrs) > 0;
        has_only         = RB_TYPE_P(only_hdrs,  T_ARRAY) && RARRAY_LEN(only_hdrs)  > 0;
        if (has_only || has_except) {
          keep_bitmap = (bool *)alloca((size_t)headers_len * sizeof(bool));
          for (long bi = 0; bi < headers_len; bi++) {
            VALUE hdr = rb_ary_entry(headers, bi);
            keep_bitmap[bi] = has_only
              ? (rb_ary_includes(only_hdrs,   hdr) == Qtrue)
              : (rb_ary_includes(except_hdrs, hdr) != Qtrue);
          }
          keep_extra_columns = !has_only;
          bool strict = RTEST(rb_hash_aref(options_hash, ID2SYM(id_strict)));
          if (has_only && !strict) {
            for (long bi = headers_len - 1; bi >= 0; bi--) {
              if (keep_bitmap[bi]) { early_exit_after = bi; break; }
            }
          }
        }
      }
    } else if (RB_TYPE_P(keep_cols_val, T_ARRAY) && headers_len > 0 && headers_len <= 4096) {
      /* Backward-compat: _keep_cols Array from direct C API callers — O(headers_len) Ruby calls */
      keep_bitmap = (bool *)alloca((size_t)headers_len * sizeof(bool));
      long prebuilt_len = RARRAY_LEN(keep_cols_val);
      for (long bi = 0; bi < headers_len; bi++) {
        keep_bitmap[bi] = bi < prebuilt_len ? RTEST(rb_ary_entry(keep_cols_val, bi)) : false;
      }
      VALUE only_hdrs = rb_hash_aref(options_hash, ID2SYM(id_only_headers));
      has_only = RB_TYPE_P(only_hdrs, T_ARRAY) && RARRAY_LEN(only_hdrs) > 0;
      keep_extra_columns = !has_only;
      bool strict = RTEST(rb_hash_aref(options_hash, ID2SYM(id_strict)));
      if (has_only && !strict) {
        for (long bi = headers_len - 1; bi >= 0; bi--) {
          if (keep_bitmap[bi]) { early_exit_after = bi; break; }
        }
      }
    }
  }
  /* else: _keep_cols is false — no filtering, keep_bitmap stays NULL. COMMON CASE. */

  bool did_early_exit = false; /* set to true when early exit fires */

  /* ----------------------------------------
   * SECTION 3: Initialize hash and tracking variables
   * ----------------------------------------
   * Hash is lazily allocated on first field insertion to avoid
   * rb_hash_new_capa + GC registration for rows that are entirely blank
   * or filtered out (all values removed by transforms).
   */
  long hash_size = headers_len > 0 ? headers_len : 16;
  long element_count = 0;                        // Number of fields parsed
  bool all_blank = true;                         // Track if all fields are blank

  // Transformation options struct — shared across all field-insertion call sites
  field_transform_opts xform = {
    .hash = Qnil,                                // Lazily allocated on first insert
    .headers = headers,
    .numeric_keys = numeric_keys,
    .encoding = encoding,
    .prefix_str = prefix_str,
    .headers_len = headers_len,
    .hash_capa = hash_size,
    .numeric_mode = numeric_mode,
    .remove_empty_values = remove_empty_values,
    .remove_zero_values = remove_zero_values,
  };

  /* ========================================
   * SECTION 4: FAST PATH - No quotes, single-char separator
   * ========================================
   * This is the common case for most CSV files. We use memchr() for fast
   * separator scanning, avoiding character-by-character iteration.
   *
   * __builtin_expect hints to the compiler that this branch is likely taken.
   */
  if (__builtin_expect(!has_quotes && col_sep_len == 1, 1)) {
    char sep = *col_sepP;
    char *sep_pos = NULL;

    /* Loop through each field by finding separator positions.
     * Two sub-paths to avoid per-field overhead in the common case:
     *   (a) no filter + no early exit → pure memchr loop, zero extra branches
     *   (b) filter active             → bitmap/early-exit checks per field
     */
    if (__builtin_expect(keep_bitmap == NULL && early_exit_after < 0, 1)) {
      /* --- (a) Common path: no column filter, no early exit --- */
      while ((sep_pos = memchr(p, sep, endP - p))) {
        long field_len   = sep_pos - startP;
        char *trim_start = startP;
        char *trim_end   = startP + field_len - 1;
        if (strip_ws) {
          while (trim_start <= trim_end && (*trim_start == ' ' || *trim_start == '\t')) trim_start++;
          while (trim_end >= trim_start && (*trim_end == ' ' || *trim_end == '\t')) trim_end--;
        }
        long trimmed_len = (trim_end >= trim_start) ? (trim_end - trim_start + 1) : 0;
        if (insert_field_into_hash(&xform, trim_start, trimmed_len, element_count, false, quote_char_val, encoding))
          all_blank = false;
        element_count++;
        p = sep_pos + 1; startP = p;
      }
      /* Process last field */
      {
        long field_len   = endP - startP;
        char *trim_start = startP;
        char *trim_end   = startP + field_len - 1;
        if (strip_ws) {
          while (trim_start <= trim_end && (*trim_start == ' ' || *trim_start == '\t')) trim_start++;
          while (trim_end >= trim_start && (*trim_end == ' ' || *trim_end == '\t')) trim_end--;
        }
        long trimmed_len = (trim_end >= trim_start) ? (trim_end - trim_start + 1) : 0;
        if (insert_field_into_hash(&xform, trim_start, trimmed_len, element_count, false, quote_char_val, encoding))
          all_blank = false;
        element_count++;
      }
    } else {
      /* --- (b) Filter path: column bitmap and/or early exit active --- */
      while ((sep_pos = memchr(p, sep, endP - p))) {
        long field_len   = sep_pos - startP;
        char *trim_start = startP;
        char *trim_end   = startP + field_len - 1;
        if (strip_ws) {
          while (trim_start <= trim_end && (*trim_start == ' ' || *trim_start == '\t')) trim_start++;
          while (trim_end >= trim_start && (*trim_end == ' ' || *trim_end == '\t')) trim_end--;
        }
        long trimmed_len = (trim_end >= trim_start) ? (trim_end - trim_start + 1) : 0;
        if (!keep_bitmap || (element_count < headers_len ? keep_bitmap[element_count] : keep_extra_columns)) {
          if (insert_field_into_hash(&xform, trim_start, trimmed_len, element_count, false, quote_char_val, encoding))
            all_blank = false;
        }
        element_count++;
        if (early_exit_after >= 0 && element_count > early_exit_after) {
          did_early_exit = true;
          break;
        }
        p = sep_pos + 1; startP = p;
      }
      /* Process last field — skip on early exit */
      if (!did_early_exit) {
        long field_len   = endP - startP;
        char *trim_start = startP;
        char *trim_end   = startP + field_len - 1;
        if (strip_ws) {
          while (trim_start <= trim_end && (*trim_start == ' ' || *trim_start == '\t')) trim_start++;
          while (trim_end >= trim_start && (*trim_end == ' ' || *trim_end == '\t')) trim_end--;
        }
        long trimmed_len = (trim_end >= trim_start) ? (trim_end - trim_start + 1) : 0;
        if (!keep_bitmap || (element_count < headers_len ? keep_bitmap[element_count] : keep_extra_columns)) {
          if (insert_field_into_hash(&xform, trim_start, trimmed_len, element_count, false, quote_char_val, encoding))
            all_blank = false;
        }
        element_count++;
      }
    }

  } else {
    /* ========================================
     * SECTION 5: SLOW PATH - Quoted fields or multi-char separator
     * ========================================
     * This handles complex cases:
     * - Fields containing the separator inside quotes: "hello,world"
     * - Multi-character separators like "::" or "\t\t"
     * - Escaped quotes using backslash: \"
     *
     * We must scan character-by-character to track quote state.
     *
     * quote_escaping and quote_boundary options are only needed here (Section 4
     * fast path never touches them), so we extract them lazily on first Section 5 entry.
     */
    VALUE quote_escaping_val = rb_hash_aref(options_hash, ID2SYM(id_quote_escaping));
    if (RB_TYPE_P(quote_escaping_val, T_SYMBOL)) {
      allow_escaped_quotes = (SYM2ID(quote_escaping_val) == id_backslash);
    }
    VALUE quote_boundary_val = rb_hash_aref(options_hash, ID2SYM(id_quote_boundary));
    quote_boundary_standard = (RB_TYPE_P(quote_boundary_val, T_SYMBOL) &&
                               SYM2ID(quote_boundary_val) == id_standard);
    /* row_sep reused from chomp above for the closing-quote boundary check */
    char *row_sepP2 = (RB_TYPE_P(row_sep, T_STRING)) ? RSTRING_PTR(row_sep) : NULL;
    long row_sep_len2 = (row_sepP2) ? RSTRING_LEN(row_sep) : 0;

    /* Opt #5 (C-side): if backslash mode is requested but the (chomped) line contains
     * no backslash character, backslash escaping cannot possibly affect parsing — a
     * backslash only matters immediately before a quote char. Downgrade to RFC mode
     * so the memchr-inside-quotes optimisation fires unconditionally for such lines.
     * This replaces the Ruby-side line.include?('\\') pre-scan that was on the hot
     * path: now the check happens here in C (one fast memchr), and only for lines
     * that actually reach Section 5 (i.e. lines that contain quote characters).
     * Unquoted lines never enter Section 5, so they pay zero cost for this check. */
    if (allow_escaped_quotes && !memchr(startP, '\\', endP - startP)) {
      allow_escaped_quotes = false;
    }

    long i;
    long backslash_count = 0;    // Track consecutive backslashes for escape detection
    bool in_quotes = false;      // Are we inside a quoted field?
    bool col_sep_found = true;
    bool field_started = false;  // for quote_boundary_standard: true once field has non-boundary content

    /* Cache first separator byte for fast pre-filtering */
    char sep_char_slow = *col_sepP;

    /* Scan through the line character by character */
    while (p < endP) {
      // Separator check: when in_quotes we can never be at a field boundary,
      // so skip the comparison entirely.
      // For single-char separator: direct byte compare.
      // For multi-char separator: pre-filter on first byte, then check the rest.
      if (!in_quotes && *p == sep_char_slow) {
        col_sep_found = true;
        for (i = 1; (i < col_sep_len) && (p + i < endP); i++) {
          if (*(p + i) != *(col_sepP + i)) { col_sep_found = false; break; }
        }
      } else {
        col_sep_found = false;
      }

      // Found separator — !in_quotes is guaranteed by the block above
      if (col_sep_found) {
        long field_len = p - startP;
        char *raw_field = startP;

        // Check if field is wrapped in quotes: "value"
        bool quoted = (field_len >= 2 && raw_field[0] == quote_char_val && raw_field[field_len - 1] == quote_char_val);
        if (quoted) {
          raw_field++;       // Skip opening quote
          field_len -= 2;    // Exclude both quotes from length
        }

        char *trim_start = raw_field;
        char *trim_end = raw_field + field_len - 1;

        if (strip_ws) {
          while (trim_start <= trim_end && (*trim_start == ' ' || *trim_start == '\t')) trim_start++;
          while (trim_end >= trim_start && (*trim_end == ' ' || *trim_end == '\t')) trim_end--;
        }

        long trimmed_len = (trim_end >= trim_start) ? (trim_end - trim_start + 1) : 0;

        // Determine if field contains embedded quotes (need unescape)
        bool has_embedded_quotes = quoted || (trimmed_len > 0 && memchr(trim_start, quote_char_val, trimmed_len));

        if (!keep_bitmap || (element_count < headers_len ? keep_bitmap[element_count] : keep_extra_columns)) {
          if (insert_field_into_hash(&xform, trim_start, trimmed_len, element_count, has_embedded_quotes, quote_char_val, encoding))
            all_blank = false;
        }
        element_count++;

        /* Early exit: all required columns already collected — stop scanning */
        if (early_exit_after >= 0 && element_count > early_exit_after) {
          did_early_exit = true;
          goto section5_done;
        }

        // Move past the separator to start of next field
        p += col_sep_len;
        startP = p;
        backslash_count = 0;
        field_started = false;   // reset for next field

      } else {
        /* Not at a separator (or inside quotes) - track quote state */

        /* RFC mode: inside quoted field, skip ahead to the next quote char.
         * Everything between here and the next quote is plain field content — no
         * separators or backslashes can appear (allow_escaped_quotes is false).
         * memchr() is SIMD-accelerated and handles typical field lengths in 1 call. */
        if (!allow_escaped_quotes && in_quotes) {
          char *next_quote = (char *)memchr(p, quote_char_val, endP - p);
          if (!next_quote) { p = endP; continue; }  /* no closing quote → unclosed */
          p = next_quote;  /* jump to quote char; fall through to quote-handling code */
        }

        if (allow_escaped_quotes && *p == '\\') {
          // Count consecutive backslashes for escape sequence detection
          backslash_count++;
          if (__builtin_expect(quote_boundary_standard, 1) && !in_quotes) field_started = true;
        } else {
          if (*p == quote_char_val) {
            if (!allow_escaped_quotes || backslash_count % 2 == 0) {
              if (__builtin_expect(quote_boundary_standard, 1)) {
                if (in_quotes) {
                  // closing quote: only valid if followed by col_sep, row_sep, or end of line
                  bool valid_close = (p + 1 >= endP);
                  if (!valid_close) {
                    valid_close = true;
                    for (long j = 0; j < col_sep_len; j++) {
                      if (*(p + 1 + j) != *(col_sepP + j)) { valid_close = false; break; }
                    }
                  }
                  if (!valid_close && row_sep_len2 > 0) {
                    valid_close = true;
                    for (long j = 0; j < row_sep_len2; j++) {
                      if (*(p + 1 + j) != *(row_sepP2 + j)) { valid_close = false; break; }
                    }
                  }
                  if (valid_close) {
                    in_quotes = false;
                    field_started = true;
                  }
                  // else: quote inside quoted field → literal (handles "" doubling)
                } else if (!field_started) {
                  in_quotes = true;     // opening quote at field boundary
                  field_started = true;
                }
                // else: mid-field quote → treat as literal
              } else {
                in_quotes = !in_quotes;
              }
            }
          } else if (__builtin_expect(quote_boundary_standard, 1) && !in_quotes) {
            if (strip_ws) {
              if (*p != ' ' && *p != '\t') {
                field_started = true;
              } else if (!field_started) {
                startP = p + 1; /* advance past leading whitespace so quote-detection at extraction sees the quote */
              }
            } else {
              field_started = true;
            }
          }
          backslash_count = 0;
        }
        p++;
      }
    }

    section5_done:;
    /* Unclosed quote at end of line (skip check on early exit):
     * Signal "needs more data" — the caller stitches the next physical line and re-parses.
     * We return [nil, -1] rather than raising so the read loop can handle multiline fields
     * without a separate pre-scan pass (detect_multiline). */
    if (!did_early_exit && in_quotes) {
      VALUE result = rb_ary_new_capa(2);
      rb_ary_push(result, Qnil);
      rb_ary_push(result, LONG2FIX(-1));
      return result;
    }

    /* Process the last field (same logic as above) — skip on early exit */
    if (!did_early_exit) {
      long field_len = endP - startP;
      char *raw_field = startP;

      bool quoted = (field_len >= 2 && raw_field[0] == quote_char_val && raw_field[field_len - 1] == quote_char_val);
      if (quoted) {
        raw_field++;
        field_len -= 2;
      }

      char *trim_start = raw_field;
      char *trim_end = raw_field + field_len - 1;

      if (strip_ws) {
        while (trim_start <= trim_end && (*trim_start == ' ' || *trim_start == '\t')) trim_start++;
        while (trim_end >= trim_start && (*trim_end == ' ' || *trim_end == '\t')) trim_end--;
      }

      long trimmed_len = (trim_end >= trim_start) ? (trim_end - trim_start + 1) : 0;

      bool has_embedded_quotes = quoted || (trimmed_len > 0 && memchr(trim_start, quote_char_val, trimmed_len));

      if (!keep_bitmap || (element_count < headers_len ? keep_bitmap[element_count] : keep_extra_columns)) {
        if (insert_field_into_hash(&xform, trim_start, trimmed_len, element_count, has_embedded_quotes, quote_char_val, encoding))
          all_blank = false;
      }
      element_count++;
    }
  }

  /* ----------------------------------------
   * SECTION 6: Handle blank rows
   * ----------------------------------------
   * If remove_empty_hashes is enabled and all fields were blank,
   * return nil instead of the hash so the row can be skipped.
   * With lazy allocation, if all_blank is true, xform.hash is still Qnil —
   * no hash was ever allocated.
   */
  if (remove_empty && all_blank) {
    VALUE result = rb_ary_new_capa(2);
    rb_ary_push(result, Qnil);
    rb_ary_push(result, LONG2FIX(element_count));
    return result;
  }

  /* ----------------------------------------
   * SECTION 7: Pad hash with nil for missing columns (conditional)
   * ----------------------------------------
   * Only add nil for missing columns when remove_empty_values is false.
   * When remove_empty_values is true, nils would be removed anyway by
   * hash_transformations, so we skip this for efficiency.
   */
  if (!remove_empty_values) {
    ensure_hash_allocated(&xform);
    for (long i = element_count; i < headers_len; i++) {
      if (!keep_bitmap || keep_bitmap[i]) {
        rb_hash_aset(xform.hash, rb_ary_entry(headers, i), Qnil);
      }
    }
  }

  /* ----------------------------------------
   * SECTION 8: Return result
   * ----------------------------------------
   * Return [hash, element_count] so caller can detect extra columns
   * (when element_count > headers_len) and extend headers if needed.
   */
  VALUE result = rb_ary_new_capa(2);
  rb_ary_push(result, xform.hash);
  rb_ary_push(result, LONG2FIX(element_count));
  return result;
}

/* ================================================================================
 * new_parse_context_c(headers, options_hash) → ParseContext
 *
 * Extracts all loop-invariant options from the options_hash once and stores them
 * in a C struct wrapped as a TypedData Ruby object.  Called once per file after
 * headers are known.  The returned context is passed to parse_line_to_hash_ctx_c
 * on every row, eliminating ~10 rb_hash_aref calls per row.
 * ================================================================================ */
__attribute__((cold)) static VALUE rb_new_parse_context(VALUE self, VALUE headers, VALUE options_hash) {
  parse_context_t *ctx;
  VALUE ctx_obj = TypedData_Make_Struct(rb_cObject, parse_context_t, &parse_context_type, ctx);

  /* Initialize all fields to safe defaults */
  memset(ctx, 0, sizeof(parse_context_t));
  ctx->headers          = headers;
  ctx->numeric_keys     = Qnil;
  ctx->keep_bitmap      = NULL;
  ctx->early_exit_after = -1;
  ctx->keep_extra_columns = true;

  /* col_sep */
  VALUE col_sep_val = rb_hash_aref(options_hash, ID2SYM(id_col_sep));
  if (RB_TYPE_P(col_sep_val, T_STRING)) {
    long len = RSTRING_LEN(col_sep_val);
    if (len > (long)(sizeof(ctx->col_sep_buf) - 1)) len = (long)(sizeof(ctx->col_sep_buf) - 1);
    memcpy(ctx->col_sep_buf, RSTRING_PTR(col_sep_val), (size_t)len);
    ctx->col_sep_buf[len] = '\0';
    ctx->col_sep_len = (int)len;
  } else {
    ctx->col_sep_buf[0] = ',';
    ctx->col_sep_buf[1] = '\0';
    ctx->col_sep_len    = 1;
  }

  /* quote_char */
  VALUE quote_char_v = rb_hash_aref(options_hash, ID2SYM(id_quote_char));
  ctx->quote_char_val = (RB_TYPE_P(quote_char_v, T_STRING) && RSTRING_LEN(quote_char_v) > 0)
                         ? RSTRING_PTR(quote_char_v)[0] : '"';

  /* row_sep */
  VALUE row_sep_v = rb_hash_aref(options_hash, ID2SYM(id_row_sep));
  if (RB_TYPE_P(row_sep_v, T_STRING)) {
    long len = RSTRING_LEN(row_sep_v);
    if (len > (long)(sizeof(ctx->row_sep_buf) - 1)) len = (long)(sizeof(ctx->row_sep_buf) - 1);
    memcpy(ctx->row_sep_buf, RSTRING_PTR(row_sep_v), (size_t)len);
    ctx->row_sep_buf[len] = '\0';
    ctx->row_sep_len = (int)len;
  }

  /* missing_header_prefix */
  VALUE header_prefix = rb_hash_aref(options_hash, ID2SYM(id_missing_header_prefix));
  if (NIL_P(header_prefix)) {
    ctx->prefix_str = "column_";
  } else {
    long len = RSTRING_LEN(header_prefix);
    if (len > (long)(sizeof(ctx->prefix_buf) - 1)) len = (long)(sizeof(ctx->prefix_buf) - 1);
    memcpy(ctx->prefix_buf, RSTRING_PTR(header_prefix), (size_t)len);
    ctx->prefix_buf[len] = '\0';
    ctx->prefix_str = ctx->prefix_buf;
  }

  /* Boolean flags */
  ctx->strip_ws            = RTEST(rb_hash_aref(options_hash, ID2SYM(id_strip_whitespace)));
  ctx->remove_empty        = RTEST(rb_hash_aref(options_hash, ID2SYM(id_remove_empty_hashes)));
  ctx->remove_empty_values = RTEST(rb_hash_aref(options_hash, ID2SYM(id_remove_empty_values)));
  ctx->remove_zero_values  = RTEST(rb_hash_aref(options_hash, ID2SYM(id_remove_zero_values)));

  /* Numeric conversion */
  VALUE convert_opt = rb_hash_aref(options_hash, ID2SYM(id_convert_values_to_numeric));
  if (RTEST(convert_opt)) {
    if (RB_TYPE_P(convert_opt, T_HASH)) {
      VALUE only_keys  = rb_hash_aref(convert_opt, ID2SYM(id_only));
      VALUE except_keys = rb_hash_aref(convert_opt, ID2SYM(id_except));
      if (RTEST(only_keys)) {
        ctx->numeric_mode = 2;
        ctx->numeric_keys = rb_Array(only_keys);
      } else if (RTEST(except_keys)) {
        ctx->numeric_mode = 3;
        ctx->numeric_keys = rb_Array(except_keys);
      }
    } else {
      ctx->numeric_mode = 1;
    }
  }

  /* quote_escaping → allow_escaped_quotes */
  VALUE quote_escaping_val = rb_hash_aref(options_hash, ID2SYM(id_quote_escaping));
  if (RB_TYPE_P(quote_escaping_val, T_SYMBOL)) {
    ctx->allow_escaped_quotes = (SYM2ID(quote_escaping_val) == id_backslash);
  }

  /* quote_boundary */
  VALUE quote_boundary_val = rb_hash_aref(options_hash, ID2SYM(id_quote_boundary));
  ctx->quote_boundary_standard = (RB_TYPE_P(quote_boundary_val, T_SYMBOL) &&
                                   SYM2ID(quote_boundary_val) == id_standard);

  /* Column filter bitmap */
  long headers_len = NIL_P(headers) ? 0 : RARRAY_LEN(headers);
  ctx->hash_capa = headers_len > 0 ? headers_len : 16;

  VALUE keep_cols_val = rb_hash_aref(options_hash, ID2SYM(id_keep_cols));
  if (keep_cols_val != Qfalse) {
    if (NIL_P(keep_cols_val)) {
      /* nil: reader.rb filter path — check _keep_bitmap, or fall back to deriving it. */
      VALUE prebuilt_bitmap = rb_hash_aref(options_hash, ID2SYM(id_keep_bitmap));
      if (RB_TYPE_P(prebuilt_bitmap, T_STRING)
          && headers_len > 0 && RSTRING_LEN(prebuilt_bitmap) >= headers_len) {
        ctx->keep_bitmap = (bool *)xmalloc((size_t)headers_len * sizeof(bool));
        ctx->keep_bitmap_len = headers_len;
        memcpy(ctx->keep_bitmap, RSTRING_PTR(prebuilt_bitmap), (size_t)headers_len * sizeof(bool));
        VALUE kec = rb_hash_aref(options_hash, ID2SYM(id_keep_extra_cols));
        ctx->keep_extra_columns = NIL_P(kec) ? true : RTEST(kec);
        VALUE exa = rb_hash_aref(options_hash, ID2SYM(id_early_exit_after_sym));
        ctx->early_exit_after = RB_INTEGER_TYPE_P(exa) ? NUM2LONG(exa) : -1;
        ctx->has_only = !ctx->keep_extra_columns;
      } else if (headers_len > 0 && headers_len <= 4096) {
        /* Last resort: derive from only_headers/except_headers directly. */
        VALUE only_hdrs  = rb_hash_aref(options_hash, ID2SYM(id_only_headers));
        VALUE except_hdrs = rb_hash_aref(options_hash, ID2SYM(id_except_headers));
        bool has_except  = RB_TYPE_P(except_hdrs, T_ARRAY) && RARRAY_LEN(except_hdrs) > 0;
        ctx->has_only    = RB_TYPE_P(only_hdrs,  T_ARRAY) && RARRAY_LEN(only_hdrs)  > 0;
        if (ctx->has_only || has_except) {
          ctx->keep_bitmap = (bool *)xmalloc((size_t)headers_len * sizeof(bool));
          ctx->keep_bitmap_len = headers_len;
          for (long bi = 0; bi < headers_len; bi++) {
            VALUE hdr = rb_ary_entry(headers, bi);
            ctx->keep_bitmap[bi] = ctx->has_only
              ? (rb_ary_includes(only_hdrs,  hdr) == Qtrue)
              : (rb_ary_includes(except_hdrs, hdr) != Qtrue);
          }
          ctx->keep_extra_columns = !ctx->has_only;
          bool strict = RTEST(rb_hash_aref(options_hash, ID2SYM(id_strict)));
          if (ctx->has_only && !strict) {
            for (long bi = headers_len - 1; bi >= 0; bi--) {
              if (ctx->keep_bitmap[bi]) { ctx->early_exit_after = bi; break; }
            }
          }
        }
      }
    } else if (RB_TYPE_P(keep_cols_val, T_ARRAY) && headers_len > 0 && headers_len <= 4096) {
      /* Backward-compat: _keep_cols Array from direct C API callers */
      ctx->keep_bitmap = (bool *)xmalloc((size_t)headers_len * sizeof(bool));
      ctx->keep_bitmap_len = headers_len;
      long prebuilt_len = RARRAY_LEN(keep_cols_val);
      for (long bi = 0; bi < headers_len; bi++) {
        ctx->keep_bitmap[bi] = bi < prebuilt_len ? RTEST(rb_ary_entry(keep_cols_val, bi)) : false;
      }
      VALUE only_hdrs = rb_hash_aref(options_hash, ID2SYM(id_only_headers));
      ctx->has_only = RB_TYPE_P(only_hdrs, T_ARRAY) && RARRAY_LEN(only_hdrs) > 0;
      ctx->keep_extra_columns = !ctx->has_only;
      bool strict = RTEST(rb_hash_aref(options_hash, ID2SYM(id_strict)));
      if (ctx->has_only && !strict) {
        for (long bi = headers_len - 1; bi >= 0; bi--) {
          if (ctx->keep_bitmap[bi]) { ctx->early_exit_after = bi; break; }
        }
      }
    }
  }
  /* else: _keep_cols == false — no filtering; keep_bitmap stays NULL */

  return ctx_obj;
}

/* ================================================================================
 * parse_line_to_hash_ctx_c(line, ctx) → [hash, data_size]
 *
 * High-performance variant of parse_line_to_hash_c that reads all loop-invariant
 * options from a pre-built ParseContext object instead of calling rb_hash_aref on
 * every row.  Eliminates ~10 rb_hash_aref calls per row from the critical path.
 *
 * ctx must be a ParseContext built by new_parse_context_c(headers, options_hash).
 * headers_len is re-read each call from RARRAY_LEN(ctx->headers) to handle extra
 * column growth without requiring a context rebuild.
 * ================================================================================ */
__attribute__((hot)) static VALUE rb_parse_line_to_hash_ctx(VALUE self, VALUE line, VALUE ctx_obj) {
  parse_context_t *ctx;
  TypedData_Get_Struct(ctx_obj, parse_context_t, &parse_context_type, ctx);

  /* ----------------------------------------
   * SECTION 1: Handle nil/invalid input
   * ---------------------------------------- */
  if (NIL_P(line)) {
    VALUE result = rb_ary_new_capa(2);
    rb_ary_push(result, Qnil);
    rb_ary_push(result, INT2FIX(0));
    return result;
  }

  if (RB_TYPE_P(line, T_STRING) != 1) {
    rb_raise(rb_eTypeError, "ERROR in SmarterCSV.parse_line_to_hash: line has to be a string or nil");
  }

  /* ----------------------------------------
   * SECTION 2: Read options from context (zero rb_hash_aref calls)
   * ----------------------------------------
   * All loop-invariant options are read directly from the pre-built struct.
   * No Hash lookups.  No Ruby object allocation.  Pure C struct field reads.
   */
  char *col_sepP          = ctx->col_sep_buf;
  long  col_sep_len       = (long)ctx->col_sep_len;
  char  quote_char_val    = ctx->quote_char_val;
  const char *prefix_str  = ctx->prefix_str;
  bool strip_ws            = ctx->strip_ws;
  bool remove_empty        = ctx->remove_empty;
  bool remove_empty_values = ctx->remove_empty_values;
  bool remove_zero_values  = ctx->remove_zero_values;
  int  numeric_mode        = ctx->numeric_mode;
  VALUE numeric_keys       = ctx->numeric_keys;
  bool *keep_bitmap         = ctx->keep_bitmap;
  bool  keep_extra_columns  = ctx->keep_extra_columns;
  long  early_exit_after    = ctx->early_exit_after;

  /* allow_escaped_quotes starts from context; per-line Opt #5 may downgrade it */
  bool allow_escaped_quotes    = ctx->allow_escaped_quotes;
  bool quote_boundary_standard = ctx->quote_boundary_standard;

  rb_encoding *encoding = rb_enc_get(line);
  char *startP = RSTRING_PTR(line);
  long  line_len = RSTRING_LEN(line);
  char *endP    = startP + line_len;
  char *p       = startP;

  /* Chomp: strip trailing row separator (pointer adjustment, no string mutation) */
  if (ctx->row_sep_len > 0) {
    long rsl = (long)ctx->row_sep_len;
    if (line_len >= rsl && memcmp(endP - rsl, ctx->row_sep_buf, (size_t)rsl) == 0) {
      endP -= rsl;
    }
  }

  /* Re-read headers_len each call to handle extra-column growth */
  long headers_len = NIL_P(ctx->headers) ? 0 : RARRAY_LEN(ctx->headers);
  VALUE headers    = ctx->headers;

  /* Check if line contains quote characters (per-line; cannot be precomputed) */
  bool has_quotes = (memchr(startP, quote_char_val, line_len) != NULL);

  bool did_early_exit = false;

  /* ----------------------------------------
   * SECTION 3: Initialize hash and tracking variables
   * ---------------------------------------- */
  long hash_size     = headers_len > 0 ? headers_len : 16;
  long element_count = 0;
  bool all_blank     = true;

  field_transform_opts xform = {
    .hash              = Qnil,
    .headers           = headers,
    .numeric_keys      = numeric_keys,
    .encoding          = encoding,
    .prefix_str        = prefix_str,
    .headers_len       = headers_len,
    .hash_capa         = hash_size,
    .numeric_mode      = numeric_mode,
    .remove_empty_values = remove_empty_values,
    .remove_zero_values  = remove_zero_values,
  };

  /* ========================================
   * SECTION 4: FAST PATH - No quotes, single-char separator
   * Two sub-paths to avoid per-field overhead in the common case:
   *   (a) no filter + no early exit → pure memchr loop, zero extra branches
   *   (b) filter active             → bitmap/early-exit checks per field
   * ======================================== */
  if (__builtin_expect(!has_quotes && col_sep_len == 1, 1)) {
    char sep      = *col_sepP;
    char *sep_pos = NULL;

    if (__builtin_expect(keep_bitmap == NULL && early_exit_after < 0, 1)) {
      /* --- (a) Common path: no column filter, no early exit --- */
      while ((sep_pos = memchr(p, sep, endP - p))) {
        long  field_len  = sep_pos - startP;
        char *trim_start = startP;
        char *trim_end   = startP + field_len - 1;
        if (strip_ws) {
          while (trim_start <= trim_end && (*trim_start == ' ' || *trim_start == '\t')) trim_start++;
          while (trim_end >= trim_start && (*trim_end == ' ' || *trim_end == '\t')) trim_end--;
        }
        long trimmed_len = (trim_end >= trim_start) ? (trim_end - trim_start + 1) : 0;
        if (insert_field_into_hash(&xform, trim_start, trimmed_len, element_count, false, quote_char_val, encoding))
          all_blank = false;
        element_count++;
        p = sep_pos + 1; startP = p;
      }
      /* Process last field */
      {
        long  field_len  = endP - startP;
        char *trim_start = startP;
        char *trim_end   = startP + field_len - 1;
        if (strip_ws) {
          while (trim_start <= trim_end && (*trim_start == ' ' || *trim_start == '\t')) trim_start++;
          while (trim_end >= trim_start && (*trim_end == ' ' || *trim_end == '\t')) trim_end--;
        }
        long trimmed_len = (trim_end >= trim_start) ? (trim_end - trim_start + 1) : 0;
        if (insert_field_into_hash(&xform, trim_start, trimmed_len, element_count, false, quote_char_val, encoding))
          all_blank = false;
        element_count++;
      }
    } else {
      /* --- (b) Filter path: column bitmap and/or early exit active --- */
      while ((sep_pos = memchr(p, sep, endP - p))) {
        long  field_len  = sep_pos - startP;
        char *trim_start = startP;
        char *trim_end   = startP + field_len - 1;
        if (strip_ws) {
          while (trim_start <= trim_end && (*trim_start == ' ' || *trim_start == '\t')) trim_start++;
          while (trim_end >= trim_start && (*trim_end == ' ' || *trim_end == '\t')) trim_end--;
        }
        long trimmed_len = (trim_end >= trim_start) ? (trim_end - trim_start + 1) : 0;
        if (!keep_bitmap || (element_count < headers_len ? keep_bitmap[element_count] : keep_extra_columns)) {
          if (insert_field_into_hash(&xform, trim_start, trimmed_len, element_count, false, quote_char_val, encoding))
            all_blank = false;
        }
        element_count++;
        if (early_exit_after >= 0 && element_count > early_exit_after) {
          did_early_exit = true;
          break;
        }
        p = sep_pos + 1; startP = p;
      }
      /* Process last field — skip on early exit */
      if (!did_early_exit) {
        long  field_len  = endP - startP;
        char *trim_start = startP;
        char *trim_end   = startP + field_len - 1;
        if (strip_ws) {
          while (trim_start <= trim_end && (*trim_start == ' ' || *trim_start == '\t')) trim_start++;
          while (trim_end >= trim_start && (*trim_end == ' ' || *trim_end == '\t')) trim_end--;
        }
        long trimmed_len = (trim_end >= trim_start) ? (trim_end - trim_start + 1) : 0;
        if (!keep_bitmap || (element_count < headers_len ? keep_bitmap[element_count] : keep_extra_columns)) {
          if (insert_field_into_hash(&xform, trim_start, trimmed_len, element_count, false, quote_char_val, encoding))
            all_blank = false;
        }
        element_count++;
      }
    }

  } else {
    /* ========================================
     * SECTION 5: SLOW PATH - Quoted fields or multi-char separator
     * ========================================
     * Quote escaping options are read from the context (no rb_hash_aref).
     * Opt #5: downgrade to RFC mode if backslash mode is requested but this
     * specific line contains no backslash — allows memchr skip-ahead inside quotes.
     */
    if (allow_escaped_quotes && !memchr(startP, '\\', endP - startP)) {
      allow_escaped_quotes = false;
    }

    char *row_sepP2    = (ctx->row_sep_len > 0) ? ctx->row_sep_buf : NULL;
    long  row_sep_len2 = (long)ctx->row_sep_len;

    long i;
    long backslash_count = 0;
    bool in_quotes     = false;
    bool col_sep_found = true;
    bool field_started = false;

    char sep_char_slow = *col_sepP;

    while (p < endP) {
      if (!in_quotes && *p == sep_char_slow) {
        col_sep_found = true;
        for (i = 1; (i < col_sep_len) && (p + i < endP); i++) {
          if (*(p + i) != *(col_sepP + i)) { col_sep_found = false; break; }
        }
      } else {
        col_sep_found = false;
      }

      if (col_sep_found) {
        long  field_len  = p - startP;
        char *raw_field  = startP;

        bool quoted = (field_len >= 2 && raw_field[0] == quote_char_val && raw_field[field_len - 1] == quote_char_val);
        if (quoted) {
          raw_field++;
          field_len -= 2;
        }

        char *trim_start = raw_field;
        char *trim_end   = raw_field + field_len - 1;

        if (strip_ws) {
          while (trim_start <= trim_end && (*trim_start == ' ' || *trim_start == '\t')) trim_start++;
          while (trim_end >= trim_start && (*trim_end == ' ' || *trim_end == '\t')) trim_end--;
        }

        long trimmed_len = (trim_end >= trim_start) ? (trim_end - trim_start + 1) : 0;

        bool has_embedded_quotes = quoted || (trimmed_len > 0 && memchr(trim_start, quote_char_val, trimmed_len));

        if (!keep_bitmap || (element_count < headers_len ? keep_bitmap[element_count] : keep_extra_columns)) {
          if (insert_field_into_hash(&xform, trim_start, trimmed_len, element_count, has_embedded_quotes, quote_char_val, encoding))
            all_blank = false;
        }
        element_count++;

        if (early_exit_after >= 0 && element_count > early_exit_after) {
          did_early_exit = true;
          goto section5_done_ctx;
        }

        p += col_sep_len;
        startP = p;
        backslash_count = 0;
        field_started   = false;

      } else {
        /* Not at a separator (or inside quotes) — track quote state */

        /* RFC mode: memchr skip-ahead inside quoted fields (Opt #6) */
        if (!allow_escaped_quotes && in_quotes) {
          char *next_quote = (char *)memchr(p, quote_char_val, endP - p);
          if (!next_quote) { p = endP; continue; }
          p = next_quote;  /* fall through to quote-handling code */
        }

        if (allow_escaped_quotes && *p == '\\') {
          backslash_count++;
          if (__builtin_expect(quote_boundary_standard, 1) && !in_quotes) field_started = true;
        } else {
          if (*p == quote_char_val) {
            if (!allow_escaped_quotes || backslash_count % 2 == 0) {
              if (__builtin_expect(quote_boundary_standard, 1)) {
                if (in_quotes) {
                  /* closing quote: only valid if followed by col_sep, row_sep, or end */
                  bool valid_close = (p + 1 >= endP);
                  if (!valid_close) {
                    valid_close = true;
                    for (long j = 0; j < col_sep_len; j++) {
                      if (*(p + 1 + j) != *(col_sepP + j)) { valid_close = false; break; }
                    }
                  }
                  if (!valid_close && row_sep_len2 > 0) {
                    valid_close = true;
                    for (long j = 0; j < row_sep_len2; j++) {
                      if (*(p + 1 + j) != *(row_sepP2 + j)) { valid_close = false; break; }
                    }
                  }
                  if (valid_close) {
                    in_quotes     = false;
                    field_started = true;
                  }
                  /* else: quote inside quoted field → literal (handles "" doubling) */
                } else if (!field_started) {
                  in_quotes     = true;   /* opening quote at field boundary */
                  field_started = true;
                }
                /* else: mid-field quote → treat as literal */
              } else {
                in_quotes = !in_quotes;
              }
            }
          } else if (__builtin_expect(quote_boundary_standard, 1) && !in_quotes) {
            if (strip_ws) {
              if (*p != ' ' && *p != '\t') {
                field_started = true;
              } else if (!field_started) {
                startP = p + 1;
              }
            } else {
              field_started = true;
            }
          }
          backslash_count = 0;
        }
        p++;
      }
    }

    section5_done_ctx:;
    /* Unclosed quote at end of line — signal multiline continuation */
    if (!did_early_exit && in_quotes) {
      VALUE result = rb_ary_new_capa(2);
      rb_ary_push(result, Qnil);
      rb_ary_push(result, LONG2FIX(-1));
      return result;
    }

    /* Process the last field — skip on early exit */
    if (!did_early_exit) {
      long  field_len  = endP - startP;
      char *raw_field  = startP;

      bool quoted = (field_len >= 2 && raw_field[0] == quote_char_val && raw_field[field_len - 1] == quote_char_val);
      if (quoted) {
        raw_field++;
        field_len -= 2;
      }

      char *trim_start = raw_field;
      char *trim_end   = raw_field + field_len - 1;

      if (strip_ws) {
        while (trim_start <= trim_end && (*trim_start == ' ' || *trim_start == '\t')) trim_start++;
        while (trim_end >= trim_start && (*trim_end == ' ' || *trim_end == '\t')) trim_end--;
      }

      long trimmed_len = (trim_end >= trim_start) ? (trim_end - trim_start + 1) : 0;

      bool has_embedded_quotes = quoted || (trimmed_len > 0 && memchr(trim_start, quote_char_val, trimmed_len));

      if (!keep_bitmap || (element_count < headers_len ? keep_bitmap[element_count] : keep_extra_columns)) {
        if (insert_field_into_hash(&xform, trim_start, trimmed_len, element_count, has_embedded_quotes, quote_char_val, encoding))
          all_blank = false;
      }
      element_count++;
    }
  }

  /* ----------------------------------------
   * SECTION 6: Handle blank rows
   * ---------------------------------------- */
  if (remove_empty && all_blank) {
    VALUE result = rb_ary_new_capa(2);
    rb_ary_push(result, Qnil);
    rb_ary_push(result, LONG2FIX(element_count));
    return result;
  }

  /* ----------------------------------------
   * SECTION 7: Pad hash with nil for missing columns (conditional)
   * ---------------------------------------- */
  if (!remove_empty_values) {
    ensure_hash_allocated(&xform);
    for (long i = element_count; i < headers_len; i++) {
      if (!keep_bitmap || keep_bitmap[i]) {
        rb_hash_aset(xform.hash, rb_ary_entry(headers, i), Qnil);
      }
    }
  }

  /* ----------------------------------------
   * SECTION 8: Return result
   * ---------------------------------------- */
  VALUE result = rb_ary_new_capa(2);
  rb_ary_push(result, xform.hash);
  rb_ary_push(result, LONG2FIX(element_count));
  return result;
}

// Count quote characters in a line, optionally respecting backslash escapes.
// This is a performance optimization that replaces the Ruby each_char implementation
// which creates a new String object for every character in the line.
// For a 1000-char line, this eliminates ~1000 object allocations per line.
//
// When quote_escaping is :backslash, backslash-escaped quotes are not counted.
// When quote_escaping is :double_quotes (RFC 4180 mode), backslash has no special meaning.
// NOTE: col_sep is accepted but unused — kept for API consistency with parse functions.
static VALUE rb_count_quote_chars(VALUE self, VALUE line, VALUE quote_char, VALUE col_sep, VALUE allow_escaped_quotes_val) {
  if (NIL_P(line) || NIL_P(quote_char)) return INT2FIX(0);
  if (RSTRING_LEN(quote_char) == 0) return INT2FIX(0);

  char *str = RSTRING_PTR(line);
  long len = RSTRING_LEN(line);
  char qc = RSTRING_PTR(quote_char)[0];
  bool allow_escaped_quotes = RTEST(allow_escaped_quotes_val);

  long count = 0;

  if (allow_escaped_quotes) {
    bool escaped = false;

    for (long i = 0; i < len; i++) {
      if (str[i] == '\\' && !escaped) {
        escaped = true;
      } else {
        if (str[i] == qc && !escaped) {
          count++;
        }
        escaped = false;
      }
    }
  } else {
    // :double_quotes mode — backslash has no special meaning, just count quote chars
    for (long i = 0; i < len; i++) {
      if (str[i] == qc) {
        count++;
      }
    }
  }

  return LONG2FIX(count);
}

// Dual-counting for :auto quote_escaping mode.
// Returns [escaped_count, rfc_count] where:
//   escaped_count = quote chars not preceded by odd backslashes (backslash-aware)
//   rfc_count = all quote chars (backslash has no special meaning)
// NOTE: col_sep is accepted but unused — kept for API consistency with parse functions.
static VALUE rb_count_quote_chars_auto(VALUE self, VALUE line, VALUE quote_char, VALUE col_sep) {
  if (NIL_P(line) || NIL_P(quote_char)) {
    VALUE result = rb_ary_new_capa(2);
    rb_ary_push(result, INT2FIX(0));
    rb_ary_push(result, INT2FIX(0));
    return result;
  }
  if (RSTRING_LEN(quote_char) == 0) {
    VALUE result = rb_ary_new_capa(2);
    rb_ary_push(result, INT2FIX(0));
    rb_ary_push(result, INT2FIX(0));
    return result;
  }

  char *str = RSTRING_PTR(line);
  long len = RSTRING_LEN(line);
  char qc = RSTRING_PTR(quote_char)[0];

  long rfc_count = 0;
  long escaped_count = 0;
  bool escaped = false;

  for (long i = 0; i < len; i++) {
    if (str[i] == qc) {
      rfc_count++;
      if (!escaped) escaped_count++;
      escaped = false;
    } else if (str[i] == '\\') {
      escaped = !escaped;
    } else {
      escaped = false;
    }
  }

  VALUE result = rb_ary_new_capa(2);
  rb_ary_push(result, LONG2FIX(escaped_count));
  rb_ary_push(result, LONG2FIX(rfc_count));
  return result;
}

void Init_smarter_csv(void) {
  SmarterCSV = rb_const_get(rb_cObject, rb_intern("SmarterCSV"));
  Parser = rb_const_get(SmarterCSV, rb_intern("Parser"));
  eMalformedCSVError = rb_const_get(SmarterCSV, rb_intern("MalformedCSV"));
  Qempty_string = rb_str_new_literal("");
  rb_gc_register_address(&Qempty_string);

  // Cache symbol IDs for fast options hash lookups
  id_col_sep = rb_intern("col_sep");
  id_quote_char = rb_intern("quote_char");
  id_row_sep = rb_intern("row_sep");
  id_missing_header_prefix = rb_intern("missing_header_prefix");
  id_strip_whitespace = rb_intern("strip_whitespace");
  id_remove_empty_hashes = rb_intern("remove_empty_hashes");
  id_remove_empty_values = rb_intern("remove_empty_values");
  id_quote_escaping = rb_intern("quote_escaping");
  id_convert_values_to_numeric = rb_intern("convert_values_to_numeric");
  id_remove_zero_values = rb_intern("remove_zero_values");
  id_only = rb_intern("only");
  id_except = rb_intern("except");
  id_quote_boundary = rb_intern("quote_boundary");
  id_only_headers   = rb_intern("only_headers");
  id_except_headers = rb_intern("except_headers");
  id_keep_cols          = rb_intern("_keep_cols");
  id_keep_bitmap        = rb_intern("_keep_bitmap");
  id_keep_extra_cols    = rb_intern("_keep_extra_cols");
  id_early_exit_after_sym = rb_intern("_early_exit_after");
  id_strict             = rb_intern("strict");
  id_backslash      = rb_intern("backslash");
  id_standard       = rb_intern("standard");

  rb_define_module_function(Parser, "parse_csv_line_c", rb_parse_csv_line, 9);
  rb_define_module_function(Parser, "count_quote_chars_c", rb_count_quote_chars, 4);
  rb_define_module_function(Parser, "count_quote_chars_auto_c", rb_count_quote_chars_auto, 3);
  rb_define_module_function(Parser, "zip_to_hash_c", rb_zip_to_hash, 2);
  rb_define_module_function(Parser, "parse_line_to_hash_c", rb_parse_line_to_hash, 3);
  rb_define_module_function(Parser, "new_parse_context_c", rb_new_parse_context, 2);
  rb_define_module_function(Parser, "parse_line_to_hash_ctx_c", rb_parse_line_to_hash_ctx, 2);
}
