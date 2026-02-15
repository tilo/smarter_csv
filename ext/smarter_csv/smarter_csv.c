#include "ruby.h"
#include "ruby/encoding.h"
#include "ruby/version.h"
#include <stdio.h>
#include <stdbool.h>
#include <string.h>

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

static VALUE rb_parse_csv_line(VALUE self, VALUE line, VALUE col_sep, VALUE quote_char, VALUE max_size, VALUE has_quotes_val, VALUE strip_ws_val) {
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
      if (*p == '\\') {
        backslash_count++;
      } else {
        if (*p == quote_char_val) {
          if (backslash_count % 2 == 0) {
            in_quotes = !in_quotes;
          } else if (in_quotes) {
            // Odd backslashes inside a quoted field: check if followed by
            // col_sep or end-of-string. If so, treat as closing quote. (issue #316)
            char *next = p + 1;
            if (next >= endP ||
                (next + col_sep_len <= endP && memcmp(next, col_sepP, col_sep_len) == 0)) {
              in_quotes = false;
            }
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
static VALUE rb_parse_line_to_hash(VALUE self, VALUE line, VALUE headers, VALUE col_sep,
                                    VALUE quote_char, VALUE header_prefix, VALUE has_quotes_val,
                                    VALUE strip_ws_val, VALUE remove_empty_val, VALUE remove_empty_values_val) {

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
   * SECTION 2: Extract parameters from Ruby objects
   * ----------------------------------------
   * Convert Ruby objects to C types for efficient access during parsing.
   */
  rb_encoding *encoding = rb_enc_get(line);      // Preserve string encoding
  char *startP = RSTRING_PTR(line);              // Pointer to start of current field
  long line_len = RSTRING_LEN(line);
  char *endP = startP + line_len;                // End of line marker
  char *p = startP;                              // Current parsing position

  char *col_sepP = RSTRING_PTR(col_sep);
  long col_sep_len = RSTRING_LEN(col_sep);

  char *quoteP = RSTRING_PTR(quote_char);
  char quote_char_val = quoteP[0];               // First char of quote string

  // Default prefix for extra columns is "column_" (e.g., :column_7)
  const char *prefix_str = NIL_P(header_prefix) ? "column_" : RSTRING_PTR(header_prefix);

  long headers_len = NIL_P(headers) ? 0 : RARRAY_LEN(headers);
  bool has_quotes = RTEST(has_quotes_val);       // Hint: does line contain quotes?
  bool strip_ws = RTEST(strip_ws_val);           // Strip whitespace from fields?
  bool remove_empty = RTEST(remove_empty_val);   // Skip rows with all blank values?
  bool remove_empty_values = RTEST(remove_empty_values_val); // If true, don't add nil for missing cols

  /* ----------------------------------------
   * SECTION 3: Initialize hash and tracking variables
   * ----------------------------------------
   * Pre-allocate hash with expected capacity for better performance.
   */
  long hash_size = headers_len > 0 ? headers_len : 16;
  VALUE hash = rb_hash_new_capa(hash_size);      // Pre-sized hash for efficiency
  VALUE field;                                   // Current field value
  long element_count = 0;                        // Number of fields parsed
  bool all_blank = true;                         // Track if all fields are blank

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
      char *raw_field = startP;
      char *trim_start = raw_field;
      char *trim_end = raw_field + field_len - 1;

      // Optional whitespace trimming (spaces and tabs only)
      if (strip_ws) {
        while (trim_start <= trim_end && (*trim_start == ' ' || *trim_start == '\t')) trim_start++;
        while (trim_end >= trim_start && (*trim_end == ' ' || *trim_end == '\t')) trim_end--;
      }

      long trimmed_len = (trim_end >= trim_start) ? (trim_end - trim_start + 1) : 0;

      // Create field value: use shared empty string for empty fields to reduce allocations
      field = (trimmed_len > 0) ? rb_enc_str_new(trim_start, trimmed_len, encoding) : Qempty_string;
      if (all_blank && trimmed_len > 0) all_blank = false;

      // Insert field directly into hash with appropriate key
      VALUE key = get_key_for_index(element_count, headers, headers_len, prefix_str);
      rb_hash_aset(hash, key, field);
      element_count++;

      // Move to next field
      p = sep_pos + 1;
      startP = p;
    }

    /* Process the last field (no separator after it) */
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
    if (all_blank && trimmed_len > 0) all_blank = false;

    VALUE key = get_key_for_index(element_count, headers, headers_len, prefix_str);
    rb_hash_aset(hash, key, field);
    element_count++;

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

        // Create field value, handling escaped quotes if present
        if (trimmed_len == 0) {
          field = Qempty_string;
        } else if (quoted || memchr(trim_start, quote_char_val, trimmed_len)) {
          // Field contains quotes - need to unescape doubled quotes ("" -> ")
          field = unescape_quotes(trim_start, trimmed_len, quote_char_val, encoding);
          all_blank = false;
        } else {
          field = rb_enc_str_new(trim_start, trimmed_len, encoding);
          all_blank = false;
        }

        // Insert field directly into hash
        VALUE key = get_key_for_index(element_count, headers, headers_len, prefix_str);
        rb_hash_aset(hash, key, field);
        element_count++;

        // Move past the separator to start of next field
        p += col_sep_len;
        startP = p;
        backslash_count = 0;

      } else {
        /* Not at a separator (or inside quotes) - track quote state */

        if (*p == '\\') {
          // Count consecutive backslashes for escape sequence detection
          backslash_count++;
        } else {
          if (*p == quote_char_val) {
            // Quote char toggles in_quotes state only if not escaped
            // (even number of preceding backslashes = not escaped)
            if (backslash_count % 2 == 0) {
              in_quotes = !in_quotes;
            } else if (in_quotes) {
              // Odd backslashes inside a quoted field: check if followed by
              // col_sep or end-of-string. If so, treat as closing quote. (issue #316)
              char *next = p + 1;
              if (next >= endP ||
                  (next + col_sep_len <= endP && memcmp(next, col_sepP, col_sep_len) == 0)) {
                in_quotes = false;
              }
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
      all_blank = false;
    } else {
      field = rb_enc_str_new(trim_start, trimmed_len, encoding);
      all_blank = false;
    }

    VALUE key = get_key_for_index(element_count, headers, headers_len, prefix_str);
    rb_hash_aset(hash, key, field);
    element_count++;
  }

  /* ----------------------------------------
   * SECTION 6: Handle blank rows
   * ----------------------------------------
   * If remove_empty_hashes is enabled and all fields were blank,
   * return nil instead of the hash so the row can be skipped.
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
    for (long i = element_count; i < headers_len; i++) {
      rb_hash_aset(hash, rb_ary_entry(headers, i), Qnil);
    }
  }

  /* ----------------------------------------
   * SECTION 8: Return result
   * ----------------------------------------
   * Return [hash, element_count] so caller can detect extra columns
   * (when element_count > headers_len) and extend headers if needed.
   */
  VALUE result = rb_ary_new_capa(2);
  rb_ary_push(result, hash);
  rb_ary_push(result, LONG2FIX(element_count));
  return result;
}

// Count quote characters in a line, respecting backslash escapes.
// This is a performance optimization that replaces the Ruby each_char implementation
// which creates a new String object for every character in the line.
// For a 1000-char line, this eliminates ~1000 object allocations per line.
//
// When a backslash-escaped quote (e.g. \") is followed by col_sep or end-of-string,
// it is treated as a literal backslash + closing quote, not as an escape sequence.
// This fixes issue #316 where a backslash as the last char in a quoted field
// was incorrectly treated as escaping the closing quote.
static VALUE rb_count_quote_chars(VALUE self, VALUE line, VALUE quote_char, VALUE col_sep) {
  if (NIL_P(line) || NIL_P(quote_char)) return INT2FIX(0);
  if (RSTRING_LEN(quote_char) == 0) return INT2FIX(0);

  char *str = RSTRING_PTR(line);
  long len = RSTRING_LEN(line);
  char qc = RSTRING_PTR(quote_char)[0];

  const char *col_sepP = NIL_P(col_sep) ? "," : RSTRING_PTR(col_sep);
  long col_sep_len = NIL_P(col_sep) ? 1 : RSTRING_LEN(col_sep);

  long count = 0;
  bool escaped = false;
  bool in_quotes = false;

  for (long i = 0; i < len; i++) {
    if (str[i] == '\\' && !escaped) {
      escaped = true;
    } else {
      if (str[i] == qc) {
        if (!escaped) {
          count++;
          in_quotes = !in_quotes;
        } else if (in_quotes) {
          // Backslash-escaped quote inside a quoted field: check if followed
          // by col_sep or end-of-string. If so, treat as closing quote. (issue #316)
          long next_pos = i + 1;
          if (next_pos >= len ||
              (next_pos + col_sep_len <= len && memcmp(str + next_pos, col_sepP, col_sep_len) == 0)) {
            count++;
            in_quotes = false;
          }
        }
      }
      escaped = false;
    }
  }

  return LONG2FIX(count);
}

void Init_smarter_csv(void) {
  SmarterCSV = rb_const_get(rb_cObject, rb_intern("SmarterCSV"));
  Parser = rb_const_get(SmarterCSV, rb_intern("Parser"));
  eMalformedCSVError = rb_const_get(SmarterCSV, rb_intern("MalformedCSV"));
  Qempty_string = rb_str_new_literal("");
  rb_gc_register_address(&Qempty_string);
  rb_define_module_function(Parser, "parse_csv_line_c", rb_parse_csv_line, 6);
  rb_define_module_function(Parser, "count_quote_chars_c", rb_count_quote_chars, 3);
  rb_define_module_function(Parser, "zip_to_hash_c", rb_zip_to_hash, 2);
  rb_define_module_function(Parser, "parse_line_to_hash_c", rb_parse_line_to_hash, 9);
}
