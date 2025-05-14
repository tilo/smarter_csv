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
  "SmarterCSV::Parser",
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

// Ruby: initialize(buffered_io)
static VALUE parser_initialize(VALUE self, VALUE buffered_io) {
  parser_t *p;
  TypedData_Get_Struct(self, parser_t, &parser_type, p);
  p->buffered_io = buffered_io;
  return self;
}

// Debug method for internal buffer state
static VALUE parser_debug_info(VALUE self) {
  parser_t *p;
  TypedData_Get_Struct(self, parser_t, &parser_type, p);

  return rb_sprintf("<Parser: buffer_pos=%zu, field_count=%zu>", p->buffer_pos, p->field_count);
}

// Internal: Append a single byte to the buffer
static void append_byte(parser_t *p, char byte) {
  if (p->buffer_pos < MAX_ROW_BYTES) {
    p->active_buf[p->buffer_pos++] = byte;
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

void Init_parser(void) {
  VALUE mSmarterCSV = rb_define_module("SmarterCSV");
  cParser = rb_define_class_under(mSmarterCSV, "Parser2", rb_cObject);
  rb_define_alloc_func(cParser, parser_allocate);

  rb_define_method(cParser, "initialize", parser_initialize, 1);
  rb_define_method(cParser, "debug_info", parser_debug_info, 0);
}
