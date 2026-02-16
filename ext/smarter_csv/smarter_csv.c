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
static ID id_only, id_except;

static VALUE unescape_quotes(char *str, long len, char quote_char, rb_encoding *encoding) {
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

static VALUE rb_parse_csv_line(VALUE self, VALUE line, VALUE col_sep, VALUE quote_char, VALUE max_size, VALUE has_quotes_val, VALUE strip_ws_val, VALUE allow_escaped_quotes_val) {
  if (RB_TYPE_P(line, T_NIL) == 1) {
    return rb_ary_new();
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
      return rb_ary_new();
    }
  }

  bool has_quotes = RTEST(has_quotes_val);
  bool strip_ws = RTEST(strip_ws_val);
  bool allow_escaped_quotes = RTEST(allow_escaped_quotes_val);

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

    return elements;
  }

  // === SLOW PATH: Quoted fields or multi-char separator ===
  long i;
  long backslash_count = 0;
  bool in_quotes = false;
  bool col_sep_found = true;

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
    } else {
      if (allow_escaped_quotes && *p == '\\') {
        backslash_count++;
      } else {
        if (*p == quote_char_val) {
          if (!allow_escaped_quotes || backslash_count % 2 == 0) {
            in_quotes = !in_quotes;
          }
        }
        backslash_count = 0;
      }
      p++;
    }
  }

  if (in_quotes) {
    rb_raise(eMalformedCSVError, "Unclosed quoted field detected in line: %s", StringValueCStr(line));
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

  return elements;
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
static inline bool insert_field_into_hash(
    field_transform_opts *opts,
    char *trim_start, long trimmed_len,
    long element_count, bool is_quoted,
    char quote_char_val, rb_encoding *encoding
) {
  VALUE key = get_key_for_index(element_count, opts->headers, opts->headers_len, opts->prefix_str);

  // 1. Empty/blank field handling
  // Check if field is blank: either zero-length, or all whitespace characters.
  // This matches Ruby's blank? behavior (BLANK_RE = /\A\s*\z/) which considers
  // spaces, tabs, \r, \n, \v, \f as whitespace.
  if (opts->remove_empty_values) {
    bool is_blank = true;
    for (long i = 0; i < trimmed_len; i++) {
      char c = trim_start[i];
      if (c != ' ' && c != '\t' && c != '\r' && c != '\n' && c != '\v' && c != '\f') {
        is_blank = false;
        break;
      }
    }
    if (is_blank) return false;  // skip blank value
  }

  if (trimmed_len == 0) {
    ensure_hash_allocated(opts);
    rb_hash_aset(opts->hash, key, Qempty_string);
    return false;  // not a non-blank value
  }

  // 2. Quoted field: unescape and insert (no numeric conversion on raw quoted data)
  if (is_quoted) {
    VALUE field = unescape_quotes(trim_start, trimmed_len, quote_char_val, encoding);
    ensure_hash_allocated(opts);
    rb_hash_aset(opts->hash, key, field);
    return true;
  }

  // 3. String-based zero check — matches /\A0+(?:\.0+)?\z/
  // Works independently of numeric conversion: "0", "00", "0.0", "00.00" etc.
  if (opts->remove_zero_values) {
    long i = 0;
    // Must start with at least one '0'
    if (trimmed_len > 0 && trim_start[0] == '0') {
      while (i < trimmed_len && trim_start[i] == '0') i++;
      if (i == trimmed_len) return false;  // all zeros, e.g. "0", "00"
      if (trim_start[i] == '.') {
        i++;
        long dot_pos = i;
        while (i < trimmed_len && trim_start[i] == '0') i++;
        // Valid if we consumed everything AND had at least one zero after dot
        if (i == trimmed_len && i > dot_pos) return false;  // e.g. "0.0", "00.00"
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

  // 5. Not numeric: insert as string
  VALUE field = rb_enc_str_new(trim_start, trimmed_len, encoding);
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
static VALUE rb_parse_line_to_hash(VALUE self, VALUE line, VALUE headers, VALUE options_hash) {

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
  VALUE quote_escaping_val = rb_hash_aref(options_hash, ID2SYM(id_quote_escaping));
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

  // Determine if backslash-escaped quotes are allowed
  bool allow_escaped_quotes = false;
  if (RB_TYPE_P(quote_escaping_val, T_SYMBOL)) {
    allow_escaped_quotes = (SYM2ID(quote_escaping_val) == rb_intern("backslash"));
  }

  rb_encoding *encoding = rb_enc_get(line);      // Preserve string encoding
  char *startP = RSTRING_PTR(line);              // Pointer to start of current field
  long line_len = RSTRING_LEN(line);
  char *endP = startP + line_len;                // End of line marker
  char *p = startP;                              // Current parsing position

  // Chomp: strip trailing row separator (pointer adjustment, no string mutation)
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

    /* Loop through each field by finding separator positions */
    while ((sep_pos = memchr(p, sep, endP - p))) {
      // Extract field boundaries
      long field_len = sep_pos - startP;
      char *trim_start = startP;
      char *trim_end = startP + field_len - 1;

      // Optional whitespace trimming (spaces and tabs only)
      if (strip_ws) {
        while (trim_start <= trim_end && (*trim_start == ' ' || *trim_start == '\t')) trim_start++;
        while (trim_end >= trim_start && (*trim_end == ' ' || *trim_end == '\t')) trim_end--;
      }

      long trimmed_len = (trim_end >= trim_start) ? (trim_end - trim_start + 1) : 0;

      if (insert_field_into_hash(&xform, trim_start, trimmed_len, element_count, false, quote_char_val, encoding))
        all_blank = false;
      element_count++;

      // Move to next field
      p = sep_pos + 1;
      startP = p;
    }

    /* Process the last field (no separator after it) */
    {
      long field_len = endP - startP;
      char *trim_start = startP;
      char *trim_end = startP + field_len - 1;

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
    /* ========================================
     * SECTION 5: SLOW PATH - Quoted fields or multi-char separator
     * ========================================
     * This handles complex cases:
     * - Fields containing the separator inside quotes: "hello,world"
     * - Multi-character separators like "::" or "\t\t"
     * - Escaped quotes using backslash: \"
     *
     * We must scan character-by-character to track quote state.
     */
    long i;
    long backslash_count = 0;    // Track consecutive backslashes for escape detection
    bool in_quotes = false;      // Are we inside a quoted field?
    bool col_sep_found = true;

    /* Scan through the line character by character */
    while (p < endP) {
      // Check if current position matches the column separator
      col_sep_found = true;
      for (i = 0; (i < col_sep_len) && (p + i < endP); i++) {
        if (*(p + i) != *(col_sepP + i)) {
          col_sep_found = false;
          break;
        }
      }

      // Found separator and not inside quotes = end of field
      if (col_sep_found && !in_quotes) {
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

        if (insert_field_into_hash(&xform, trim_start, trimmed_len, element_count, has_embedded_quotes, quote_char_val, encoding))
          all_blank = false;
        element_count++;

        // Move past the separator to start of next field
        p += col_sep_len;
        startP = p;
        backslash_count = 0;

      } else {
        /* Not at a separator (or inside quotes) - track quote state */

        if (allow_escaped_quotes && *p == '\\') {
          // Count consecutive backslashes for escape sequence detection
          backslash_count++;
        } else {
          if (*p == quote_char_val) {
            if (!allow_escaped_quotes || backslash_count % 2 == 0) {
              in_quotes = !in_quotes;
            }
          }
          backslash_count = 0;
        }
        p++;
      }
    }

    // Error: unclosed quote at end of line
    if (in_quotes) {
      rb_raise(eMalformedCSVError, "Unclosed quoted field detected in line: %s", StringValueCStr(line));
    }

    /* Process the last field (same logic as above) */
    {
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

      if (insert_field_into_hash(&xform, trim_start, trimmed_len, element_count, has_embedded_quotes, quote_char_val, encoding))
        all_blank = false;
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
      rb_hash_aset(xform.hash, rb_ary_entry(headers, i), Qnil);
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

  rb_define_module_function(Parser, "parse_csv_line_c", rb_parse_csv_line, 7);
  rb_define_module_function(Parser, "count_quote_chars_c", rb_count_quote_chars, 4);
  rb_define_module_function(Parser, "count_quote_chars_auto_c", rb_count_quote_chars_auto, 3);
  rb_define_module_function(Parser, "zip_to_hash_c", rb_zip_to_hash, 2);
  rb_define_module_function(Parser, "parse_line_to_hash_c", rb_parse_line_to_hash, 3);
}
