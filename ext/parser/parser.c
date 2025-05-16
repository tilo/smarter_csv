// C-extension implementation of Parser with a 256KB row buffer

#include "ruby.h"
#include <string.h>

#define MAX_ROW_BYTES 262144 // 256 KB
#define MAX_FIELDS 128 * 1024 // Arbitrary upper bound of fields per row

// we design for two buffers, but only allocate one very large buffer for now.
// if we ever have a HUGE CSV row, that does not fit into buf1, we can allocate 
// buf2 with 2*MAX_ROW_BYTES and copy over the buf1 contents (leaving that for later)
typedef struct {
  char *buf1;
  char *buf2;
  char *active_buf;
  size_t buffer_pos;

  VALUE buffered_io; // reference to SmarterCSV::BufferedIO instance

  size_t field_starts[MAX_FIELDS];
  size_t field_lengths[MAX_FIELDS];
  size_t field_count;

  long col_sep_len;
  long row_sep_len;
  long quote_char_len;
  long double_quote_char_len;
  long max_sep_len;

  const char *col_sep_ptr;
  const char *row_sep_ptr;
  const char *quote_char_ptr;
  const char *double_quote_char_ptr;

  int is_ascii;
  int is_utf8;
  int is_ascii_or_utf8;  
} parser_t;

// Forward declarations for internal C functions
static VALUE parser_next_char(VALUE self);
static VALUE parser_next_chars(VALUE self, VALUE nval);
static VALUE parser_peek_chars(VALUE self, VALUE nval);
static VALUE parser_read_field_c(VALUE self);
static VALUE parser_read_row_as_fields_c(VALUE self);


static void parser_free(void *ptr) {
  parser_t *p = (parser_t *)ptr;
  if (p->buf1) free(p->buf1);
  if (p->buf2) free(p->buf2);
  free(p);
}

static VALUE cParser;

static size_t parser_memsize(const void *ptr) {
  return sizeof(parser_t) + (2 * MAX_ROW_BYTES);
}

static const rb_data_type_t parser_type = {
  "SmarterCSV::ParserC",
  {0, parser_free, parser_memsize,},
  0, 0, RUBY_TYPED_FREE_IMMEDIATELY
};

static VALUE parser_allocate(VALUE klass) {
  parser_t *p;
  VALUE obj = TypedData_Make_Struct(klass, parser_t, &parser_type, p);

  p->buf1 = malloc(MAX_ROW_BYTES);
  p->buf2 = NULL; // not used yet
  p->active_buf = p->buf1;
  p->buffer_pos = 0;
  p->field_count = 0;
  p->buffered_io = Qnil;
  p->col_sep_len = 0;
  p->row_sep_len = 0;
  p->quote_char_len = 0;
  p->double_quote_char_len = 0;  
  return obj;
}

// Internal: Append characters to the buffer
static void append_chars(parser_t *p, const char *bytes, size_t len) {
  if (p->buffer_pos + len <= MAX_ROW_BYTES) {
    memcpy(p->active_buf + p->buffer_pos, bytes, len);
    p->buffer_pos += len;
  } else {
    rb_raise(rb_eRuntimeError, "Parser buffer overflow");
  }
}

// Internal: Mark the start of a new field
static void mark_field_start(parser_t *p) {
  if (p->field_count < MAX_FIELDS) {
    p->field_starts[p->field_count] = p->buffer_pos;
  } else {
    rb_raise(rb_eRuntimeError, "Too many fields in row");
  }
}

// Internal: Finalize the current field
static void finalize_field(parser_t *p) {
  size_t start = p->field_starts[p->field_count];
  size_t len = p->buffer_pos - start;
  p->field_lengths[p->field_count] = len;
  p->field_count++;
}

// Internal: Return an array of Ruby strings representing the fields
static VALUE flush_row(parser_t *p) {
  VALUE ary = rb_ary_new2(p->field_count);
  for (size_t i = 0; i < p->field_count; ++i) {
    size_t start = p->field_starts[i];
    size_t len = p->field_lengths[i];
    VALUE str = rb_str_new(p->active_buf + start, len);
    rb_ary_push(ary, str);
  }
  p->buffer_pos = 0;
  p->field_count = 0;
  return ary;
}

// Ruby method: read_row_as_fields
static VALUE parser_read_row_as_fields_c(VALUE self) {
  parser_t *p;
  TypedData_Get_Struct(self, parser_t, &parser_type, p);

  int row_complete = 0;

  while (!row_complete) {
    VALUE sep = parser_peek_chars(self, LONG2NUM(p->max_sep_len));

    VALUE pair = parser_read_field_c(self);
    if (TYPE(pair) != T_ARRAY || RARRAY_LEN(pair) != 2) {
      rb_raise(rb_eRuntimeError, "Expected [field, field_closed] from read_field_c");
    }
    VALUE field = rb_ary_entry(pair, 0);
    VALUE field_closed = rb_ary_entry(pair, 1);
    if (field_closed == Qfalse) {
      rb_raise(rb_eRuntimeError, "Unclosed quoted field");
    }
    if (field != Qnil) {
      mark_field_start(p);
      append_chars(p, RSTRING_PTR(field), RSTRING_LEN(field));
      finalize_field(p);
    }

    sep = parser_peek_chars(self, LONG2NUM(p->max_sep_len));
    if (!NIL_P(sep) && RSTRING_LEN(sep) >= p->col_sep_len && 
        strncmp(RSTRING_PTR(sep), p->col_sep_ptr, p->col_sep_len) == 0) {
      parser_next_chars(self, INT2NUM(p->col_sep_len));
    } else if (!NIL_P(sep) && RSTRING_LEN(sep) >= p->row_sep_len && 
               strncmp(RSTRING_PTR(sep), p->row_sep_ptr, p->row_sep_len) == 0) {
      parser_next_chars(self, INT2NUM(p->row_sep_len));
      row_complete = 1;
    } else if (NIL_P(sep) || RSTRING_LEN(sep) == 0) {
      row_complete = 1;
    } else {
      rb_raise(rb_eRuntimeError, "Expected separator but found: %s", RSTRING_PTR(sep));
    }
  }

  return flush_row(p);
}

// Ruby method: read_field
static VALUE parser_read_field_c(VALUE self) {
  parser_t *p;
  TypedData_Get_Struct(self, parser_t, &parser_type, p);

  int field_started = 1;
  int field_ends_in_quote = 0;
  int field_closed = 0;

  mark_field_start(p);

  while (1) {
    VALUE peek = parser_peek_chars(self, LONG2NUM(p->max_sep_len));

    if (field_started) {
      field_ends_in_quote = !NIL_P(peek) && RSTRING_LEN(peek) >= p->quote_char_len &&
                            strncmp(RSTRING_PTR(peek), p->quote_char_ptr, p->quote_char_len) == 0;
      if (field_ends_in_quote) {
        parser_next_chars(self, INT2NUM(p->quote_char_len));
      }
      field_started = 0;
      continue;
    }

    if (NIL_P(peek)) {
      field_closed = !field_ends_in_quote;
      if (field_ends_in_quote) return rb_ary_new3(2, Qnil, Qfalse);
      break;
    }

    if (field_ends_in_quote) {
      if (RSTRING_LEN(peek) >= p->double_quote_char_len &&
          strncmp(RSTRING_PTR(peek), p->double_quote_char_ptr, p->double_quote_char_len) == 0) {
        parser_next_chars(self, INT2NUM(p->double_quote_char_len));
        append_chars(p, p->quote_char_ptr, p->quote_char_len);
      } else if (RSTRING_LEN(peek) >= p->quote_char_len &&
                 strncmp(RSTRING_PTR(peek), p->quote_char_ptr, p->quote_char_len) == 0) {
        parser_next_chars(self, INT2NUM(p->quote_char_len));
        field_closed = 1;
        break;
      } else {
        VALUE ch = parser_next_char(self);
        if (!NIL_P(ch)) append_chars(p, RSTRING_PTR(ch), RSTRING_LEN(ch));
      }
    } else {
      if (RSTRING_LEN(peek) >= p->double_quote_char_len &&
          strncmp(RSTRING_PTR(peek), p->double_quote_char_ptr, p->double_quote_char_len) == 0) {
        parser_next_chars(self, INT2NUM(p->double_quote_char_len));
        append_chars(p, p->quote_char_ptr, p->quote_char_len);
      } else if (NIL_P(peek) ||
                 (RSTRING_LEN(peek) >= p->col_sep_len &&
                  strncmp(RSTRING_PTR(peek), p->col_sep_ptr, p->col_sep_len) == 0) ||
                 (RSTRING_LEN(peek) >= p->row_sep_len &&
                  strncmp(RSTRING_PTR(peek), p->row_sep_ptr, p->row_sep_len) == 0)) {
        field_closed = 1;
        break;
      } else {
        VALUE ch = parser_next_char(self);
        if (!NIL_P(ch)) append_chars(p, RSTRING_PTR(ch), RSTRING_LEN(ch));
      }
    }
  }

  VALUE str = rb_str_new(p->active_buf + p->field_starts[p->field_count],
                         p->buffer_pos - p->field_starts[p->field_count]);
  return rb_ary_new3(2, str, field_closed ? Qtrue : Qfalse);
}

// Ruby methods: next_char, peek_chars, next_chars, skip_chars
// static VALUE parser_next_char(VALUE self) {
//   parser_t *p;
//   TypedData_Get_Struct(self, parser_t, &parser_type, p);
//   VALUE io = rb_iv_get(self, "@io");

//   // Fast-path for ASCII/UTF-8 single-byte characters
//   if (p->is_ascii_or_utf8) {
//     VALUE byte_val = rb_funcall(io, rb_intern("next_byte"), 0);
//     if (NIL_P(byte_val)) return Qnil;

//     if (RSTRING_LEN(byte_val) == 1 && ((unsigned char)RSTRING_PTR(byte_val)[0]) < 0x80) {
//       return byte_val;  // already a valid single-byte ASCII char
//     } else {
//       VALUE dup = rb_str_dup(byte_val);
//       rb_funcall(dup, rb_intern("force_encoding"), 1, rb_iv_get(self, "@encoding"));
//       return RTEST(rb_funcall(dup, rb_intern("valid_encoding?"), 0)) ? dup : Qnil;
//     }
//   }

//   // Slow-path for general encodings
//   VALUE bytes = rb_str_new("", 0);
//   for (int i = 0; i < 64; ++i) {
//     VALUE b = rb_funcall(io, rb_intern("next_byte"), 0);
//     if (NIL_P(b)) break;
//     rb_str_cat(bytes, RSTRING_PTR(b), RSTRING_LEN(b));
//     VALUE str = rb_str_dup(bytes);
//     rb_funcall(str, rb_intern("force_encoding"), 1, rb_iv_get(self, "@encoding"));
//     if (RTEST(rb_funcall(str, rb_intern("valid_encoding?"), 0))) return str;
//   }
//   return Qnil;
// }

static VALUE parser_next_char(VALUE self) {
  VALUE io = rb_iv_get(self, "@io");
  VALUE bytes = rb_str_new("", 0);

  for (int i = 0; i < 64; ++i) {
    VALUE b = rb_funcall(io, rb_intern("next_byte"), 0);
    if (NIL_P(b)) break;
    rb_str_cat(bytes, RSTRING_PTR(b), RSTRING_LEN(b));
    VALUE str = rb_str_dup(bytes);
    rb_funcall(str, rb_intern("force_encoding"), 1, rb_iv_get(self, "@encoding"));
    if (RTEST(rb_funcall(str, rb_intern("valid_encoding?"), 0))) return str;
  }
  return Qnil;
}

static VALUE parser_next_chars(VALUE self, VALUE nval) {
  int n = NUM2INT(nval);
  for (int i = 0; i < n; ++i) {
    parser_next_char(self);
  }
  return Qnil;
}

// Ruby method: peek_chars
static VALUE parser_peek_chars(VALUE self, VALUE nval) {
  int n = NUM2INT(nval);
  VALUE io = rb_iv_get(self, "@io");
  VALUE bytes = rb_funcall(io, rb_intern("peek_bytes"), 1, INT2NUM(n * 16));
  if (NIL_P(bytes) || RSTRING_LEN(bytes) == 0) return Qnil;

  VALUE str = rb_str_dup(bytes);
  rb_funcall(str, rb_intern("force_encoding"), 1, rb_iv_get(self, "@encoding"));
  if (RTEST(rb_funcall(str, rb_intern("valid_encoding?"), 0))) {
    return rb_funcall(str, rb_intern("slice"), 2, INT2NUM(0), INT2NUM(n));
  } else {
    VALUE scrubbed = rb_funcall(str, rb_intern("scrub"), 1, rb_str_new_cstr(""));
    return rb_funcall(scrubbed, rb_intern("slice"), 2, INT2NUM(0), INT2NUM(n));
  }
}

// static VALUE parser_peek_chars(VALUE self, VALUE nval) {
//   parser_t *p;
//   TypedData_Get_Struct(self, parser_t, &parser_type, p);

//   int n = NUM2INT(nval);
//   VALUE io = rb_iv_get(self, "@io");
//   VALUE bytes = rb_funcall(io, rb_intern("peek_bytes"), 1, INT2NUM(n * 16));
//   if (NIL_P(bytes) || RSTRING_LEN(bytes) == 0) return Qnil;

//   if (p->is_ascii_or_utf8 && RSTRING_LEN(bytes) >= n) {
//     VALUE substr = rb_str_substr(bytes, 0, n);
//     rb_funcall(substr, rb_intern("force_encoding"), 1, rb_iv_get(self, "@encoding"));
//     return substr;
//   }

//   VALUE str = rb_str_dup(bytes);
//   rb_funcall(str, rb_intern("force_encoding"), 1, rb_iv_get(self, "@encoding"));
//   if (RTEST(rb_funcall(str, rb_intern("valid_encoding?"), 0))) {
//     return rb_funcall(str, rb_intern("slice"), 2, INT2NUM(0), INT2NUM(n));
//   } else {
//     VALUE scrubbed = rb_funcall(str, rb_intern("scrub"), 1, rb_str_new_cstr(""));
//     return rb_funcall(scrubbed, rb_intern("slice"), 2, INT2NUM(0), INT2NUM(n));
//   }
// }

// Ruby method: read_row (returns raw string line including row_sep)
static VALUE parser_read_row(VALUE self) {
  VALUE io = rb_iv_get(self, "@io");
  VALUE row_sep = rb_iv_get(self, "@row_sep");
  VALUE encoding = rb_iv_get(self, "@encoding");

  long row_sep_len = RSTRING_LEN(row_sep);
  const char *row_sep_ptr = RSTRING_PTR(row_sep);

  VALUE buffer = rb_str_new("", 0);

  while (1) {
    VALUE byte_val = rb_funcall(io, rb_intern("next_byte"), 0);
    if (NIL_P(byte_val)) break;

    rb_str_cat(buffer, RSTRING_PTR(byte_val), RSTRING_LEN(byte_val));

    if (RSTRING_LEN(buffer) >= row_sep_len) {
      const char *buf_ptr = RSTRING_PTR(buffer);
      long buf_len = RSTRING_LEN(buffer);

      if (strncmp(buf_ptr + buf_len - row_sep_len, row_sep_ptr, row_sep_len) == 0) {
        rb_funcall(buffer, rb_intern("force_encoding"), 1, encoding);
        return buffer;
      }
    }
  }

  if (RSTRING_LEN(buffer) == 0) {
    return Qnil;
  }

  rb_funcall(buffer, rb_intern("force_encoding"), 1, encoding);
  return buffer;
}


// Ruby method: skip_rows (skips n rows and retuns nil)
static VALUE parser_skip_rows(VALUE self, VALUE nval) {
  int n = NUM2INT(nval);
  for (int i = 0; i < n; ++i) {
    parser_read_row(self);
  }
  return Qnil;
}


// Ruby: initialize(source, options)
static VALUE parser_initialize(VALUE self, VALUE source, VALUE options) {
  parser_t *p;
  TypedData_Get_Struct(self, parser_t, &parser_type, p);

  VALUE buffer_size = rb_hash_lookup(options, ID2SYM(rb_intern("buffer_size")));
  if (NIL_P(buffer_size)) buffer_size = SIZET2NUM(128 * 1024);

  VALUE buffered_io = rb_funcall(rb_path2class("SmarterCSV::BufferedIO"), rb_intern("new"), 2, source, buffer_size);
  p->buffered_io = buffered_io;

  rb_iv_set(self, "@io", buffered_io);
  rb_iv_set(self, "@buffer_size", buffer_size);
  VALUE encoding = rb_funcall(source, rb_intern("external_encoding"), 0);
  rb_iv_set(self, "@encoding", encoding);

  VALUE row_sep = rb_hash_aref(options, ID2SYM(rb_intern("row_sep")));
  VALUE col_sep = rb_hash_aref(options, ID2SYM(rb_intern("col_sep")));
  VALUE quote_char = rb_hash_aref(options, ID2SYM(rb_intern("quote_char")));
  VALUE double_quote_char = rb_funcall(quote_char, rb_intern("*"), 1, INT2NUM(2));

  rb_iv_set(self, "@row_sep", row_sep);
  rb_iv_set(self, "@col_sep", col_sep);
  rb_iv_set(self, "@quote_char", quote_char);
  rb_iv_set(self, "@double_quote_char", double_quote_char);

  long max_len = RSTRING_LEN(row_sep);
  if (RSTRING_LEN(col_sep) > max_len) max_len = RSTRING_LEN(col_sep);
  if (RSTRING_LEN(double_quote_char) > max_len) max_len = RSTRING_LEN(double_quote_char);
  rb_iv_set(self, "@max_sep_length", LONG2NUM(max_len));

  p->col_sep_len = RSTRING_LEN(col_sep);
  p->row_sep_len = RSTRING_LEN(row_sep);
  p->quote_char_len = RSTRING_LEN(quote_char);
  p->double_quote_char_len = RSTRING_LEN(double_quote_char);
  p->max_sep_len = max_len;

  p->col_sep_ptr = RSTRING_PTR(col_sep);
  p->row_sep_ptr = RSTRING_PTR(row_sep);
  p->quote_char_ptr = RSTRING_PTR(quote_char);
  p->double_quote_char_ptr = RSTRING_PTR(double_quote_char);

  const char *enc_name = RSTRING_PTR(rb_funcall(encoding, rb_intern("to_s"), 0));
  p->is_ascii = strcmp(enc_name, "US-ASCII") == 0;
  p->is_utf8 = strcmp(enc_name, "UTF-8") == 0;
  p->is_ascii_or_utf8 = (p->is_ascii || p->is_utf8);

  return self;
}

// Debug method for internal buffer state
static VALUE parser_debug_info(VALUE self) {
  parser_t *p;
  TypedData_Get_Struct(self, parser_t, &parser_type, p);

  return rb_sprintf("<Parser: buffer_pos=%zu, field_count=%zu>", p->buffer_pos, p->field_count);
}

void Init_parserc(void) {
  VALUE mSmarterCSV = rb_define_module("SmarterCSV");
  cParser = rb_define_class_under(mSmarterCSV, "ParserC", rb_cObject);
  rb_define_alloc_func(cParser, parser_allocate);

  rb_define_method(cParser, "initialize", parser_initialize, 2);
  rb_define_method(cParser, "debug_info", parser_debug_info, 0);
  rb_define_method(cParser, "read_row_as_fields", parser_read_row_as_fields_c, 0);
  rb_define_method(cParser, "read_field", parser_read_field_c, 0);

  rb_define_method(cParser, "next_char", parser_next_char, 0);
  rb_define_method(cParser, "next_chars", parser_next_chars, 1);
  rb_define_method(cParser, "skip_chars", parser_next_chars, 1);
  rb_define_method(cParser, "peek_chars", parser_peek_chars, 1);
  rb_define_method(cParser, "read_row", parser_read_row, 0);
  rb_define_method(cParser, "skip_rows", parser_skip_rows, 1);
}
