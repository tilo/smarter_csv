#include "ruby.h"
#include "ruby/encoding.h"
#include <stdio.h>
#include <stdbool.h>
#include <string.h>

#ifndef bool
  #define bool int
  #define false ((bool)0)
  #define true  ((bool)1)
#endif

VALUE SmarterCSV = Qnil;
VALUE eMalformedCSVError = Qnil;
VALUE Parser = Qnil;
VALUE Qempty_string = Qnil; // shared frozen empty string

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

      long trimmed_len = trim_end - trim_start + 1;

      field = rb_enc_str_new(trim_start, trimmed_len, encoding);
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

      long trimmed_len = trim_end - trim_start + 1;

      field = rb_enc_str_new(trim_start, trimmed_len, encoding);
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

      long trimmed_len = trim_end - trim_start + 1;

      if (quoted || memchr(trim_start, quote_char_val, trimmed_len)) {
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

    long trimmed_len = trim_end - trim_start + 1;

    if (quoted || memchr(trim_start, quote_char_val, trimmed_len)) {
      field = unescape_quotes(trim_start, trimmed_len, quote_char_val, encoding);
    } else {
      field = rb_enc_str_new(trim_start, trimmed_len, encoding);
    }

    rb_ary_push(elements, field);
  }

  return elements;
}

void Init_smarter_csv(void) {
  SmarterCSV = rb_const_get(rb_cObject, rb_intern("SmarterCSV"));
  Parser = rb_const_get(SmarterCSV, rb_intern("Parser"));
  eMalformedCSVError = rb_const_get(SmarterCSV, rb_intern("MalformedCSV"));
  Qempty_string = rb_str_new_literal("");
  rb_gc_register_address(&Qempty_string);
  rb_define_module_function(Parser, "parse_csv_line_c", rb_parse_csv_line, 6);
}
