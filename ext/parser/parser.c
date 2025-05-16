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

  VALUE col_sep = rb_iv_get(self, "@col_sep");
  VALUE row_sep = rb_iv_get(self, "@row_sep");
  VALUE max_sep_len_val = rb_iv_get(self, "@max_sep_length");

  int row_complete = 0;

  while (!row_complete) {
    VALUE sep = parser_peek_chars(self, max_sep_len_val);

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

    sep = parser_peek_chars(self, max_sep_len_val);
    if (!NIL_P(sep) && RSTRING_LEN(sep) >= RSTRING_LEN(col_sep) && 
        strncmp(RSTRING_PTR(sep), RSTRING_PTR(col_sep), RSTRING_LEN(col_sep)) == 0) {
      parser_next_chars(self, INT2NUM(RSTRING_LEN(col_sep)));
    } else if (!NIL_P(sep) && RSTRING_LEN(sep) >= RSTRING_LEN(row_sep) && 
               strncmp(RSTRING_PTR(sep), RSTRING_PTR(row_sep), RSTRING_LEN(row_sep)) == 0) {
      parser_next_chars(self, INT2NUM(RSTRING_LEN(row_sep)));
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

  VALUE buffer = rb_str_new("", 0);
  int field_started = 1;
  int field_ends_in_quote = 0;
  int field_closed = 0;

  VALUE quote_char = rb_iv_get(self, "@quote_char");
  VALUE double_quote_char = rb_iv_get(self, "@double_quote_char");
  VALUE col_sep = rb_iv_get(self, "@col_sep");
  VALUE row_sep = rb_iv_get(self, "@row_sep");
  VALUE max_sep_len_val = rb_iv_get(self, "@max_sep_length");

  while (1) {
    VALUE peek = parser_peek_chars(self, max_sep_len_val);

    if (field_started) {
      field_ends_in_quote = !NIL_P(peek) && RSTRING_LEN(peek) >= RSTRING_LEN(quote_char) &&
                            strncmp(RSTRING_PTR(peek), RSTRING_PTR(quote_char), RSTRING_LEN(quote_char)) == 0;
      if (field_ends_in_quote) {
        parser_next_chars(self, INT2NUM(RSTRING_LEN(quote_char)));
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
      if (RSTRING_LEN(peek) >= RSTRING_LEN(double_quote_char) &&
          strncmp(RSTRING_PTR(peek), RSTRING_PTR(double_quote_char), RSTRING_LEN(double_quote_char)) == 0) {
        parser_next_chars(self, INT2NUM(RSTRING_LEN(double_quote_char)));
        rb_str_cat(buffer, RSTRING_PTR(quote_char), RSTRING_LEN(quote_char));
      } else if (RSTRING_LEN(peek) >= RSTRING_LEN(quote_char) &&
                 strncmp(RSTRING_PTR(peek), RSTRING_PTR(quote_char), RSTRING_LEN(quote_char)) == 0) {
        parser_next_chars(self, INT2NUM(RSTRING_LEN(quote_char)));
        field_closed = 1;
        break;
      } else {
        VALUE ch = parser_next_char(self);
        if (!NIL_P(ch)) rb_str_cat(buffer, RSTRING_PTR(ch), RSTRING_LEN(ch));
      }
    } else {
      if (RSTRING_LEN(peek) >= RSTRING_LEN(double_quote_char) &&
          strncmp(RSTRING_PTR(peek), RSTRING_PTR(double_quote_char), RSTRING_LEN(double_quote_char)) == 0) {
        parser_next_chars(self, INT2NUM(RSTRING_LEN(double_quote_char)));
        rb_str_cat(buffer, RSTRING_PTR(quote_char), RSTRING_LEN(quote_char));
      } else if (NIL_P(peek) ||
                 (RSTRING_LEN(peek) >= RSTRING_LEN(col_sep) &&
                  strncmp(RSTRING_PTR(peek), RSTRING_PTR(col_sep), RSTRING_LEN(col_sep)) == 0) ||
                 (RSTRING_LEN(peek) >= RSTRING_LEN(row_sep) &&
                  strncmp(RSTRING_PTR(peek), RSTRING_PTR(row_sep), RSTRING_LEN(row_sep)) == 0)) {
        field_closed = 1;
        break;
      } else {
        VALUE ch = parser_next_char(self);
        if (!NIL_P(ch)) rb_str_cat(buffer, RSTRING_PTR(ch), RSTRING_LEN(ch));
      }
    }
  }

  return rb_ary_new3(2, buffer, field_closed ? Qtrue : Qfalse);
}

// Ruby methods: next_char, peek_chars, next_chars, skip_chars
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
    // VALUE scrubbed = rb_funcall(str, rb_intern("scrub"), 1, rb_str_new_cstr(""));
    // VALUE chars = rb_funcall(scrubbed, rb_intern("chars"), 0);
    // VALUE result = rb_ary_new();
    // for (int i = 0; i < n && i < RARRAY_LEN(chars); ++i) {
    //   rb_ary_push(result, rb_ary_entry(chars, i));
    // }
    // if (RARRAY_LEN(result) == 0) return Qnil;
    // return rb_funcall(result, rb_intern("join"), 0);
    VALUE scrubbed = rb_funcall(str, rb_intern("scrub"), 1, rb_str_new_cstr(""));
    return rb_funcall(scrubbed, rb_intern("slice"), 2, INT2NUM(0), INT2NUM(n));
  }
}

// Ruby method: read_row (returns raw string line including row_sep)
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
  rb_iv_set(self, "@encoding", rb_funcall(source, rb_intern("external_encoding"), 0));

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
