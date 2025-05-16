// ext/smarter_csv/buffered_io.c

#include "ruby.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>

#define BUFFER_SIZE_256K (256 * 1024)
#define BUFFER_SIZE_512K (512 * 1024)
#define BUFFER_SIZE_1MB   (1024 * 1024)
#define MAX_CARRY_ZONE 16  // multibyte, quote, newline safety

typedef enum { SOURCE_FILE_PTR, SOURCE_RUBY_IO } SmarterCSV_SourceType;

typedef struct {
  char *buffer1;
  char *buffer2;
  char *active_buf;
  char *inactive_buf;

  size_t buffer_size;
  size_t pos;
  size_t length;
  size_t carry_len;
  size_t inactive_len;

  FILE *fp;
  VALUE ruby_io;
  SmarterCSV_SourceType source_type;

  bool eof;
} SmarterCSV_Buffer;

static void buffer_free(void *ptr) {
  SmarterCSV_Buffer *b = (SmarterCSV_Buffer *)ptr;
  if (b) {
    free(b->buffer1);
    free(b->buffer2);
    if (b->source_type == SOURCE_FILE_PTR && b->fp) fclose(b->fp);
    xfree(b);
  }
}

static const rb_data_type_t buffer_type = {
  "SmarterCSV_Buffer",
  { NULL, buffer_free, NULL },
  0, 0, RUBY_TYPED_FREE_IMMEDIATELY
};

bool init_buffer(SmarterCSV_Buffer *b, size_t buffer_size) {
  b->buffer1 = calloc(1, buffer_size);
  b->buffer2 = calloc(1, buffer_size);
  if (!b->buffer1 || !b->buffer2) return false;

  b->active_buf = b->buffer1;
  b->inactive_buf = b->buffer2;
  b->buffer_size = buffer_size;
  b->pos = 0;
  b->length = 0;
  b->carry_len = 0;
  b->inactive_len = 0;
  b->eof = false;

  return true;
}

void refill_buffer(SmarterCSV_Buffer *b) {
  size_t carry_offset = 0;

  size_t remaining = b->length - b->pos;
  if (remaining > 0) {
    if (remaining > MAX_CARRY_ZONE) remaining = MAX_CARRY_ZONE;
    memcpy(b->inactive_buf, b->active_buf + b->length - remaining, remaining);
    carry_offset = remaining;
  }
  b->length = 0;

  size_t to_read = b->buffer_size - carry_offset;
  size_t bytes_read = 0;

  if (b->source_type == SOURCE_FILE_PTR) {
    bytes_read = fread(b->inactive_buf + carry_offset, 1, to_read, b->fp);
  } else if (b->source_type == SOURCE_RUBY_IO) {
    VALUE str = rb_funcall(b->ruby_io, rb_intern("read"), 1, SIZET2NUM(to_read));
    if (!NIL_P(str)) {
      bytes_read = RSTRING_LEN(str);
      memcpy(b->inactive_buf + carry_offset, RSTRING_PTR(str), bytes_read);
    }
  }

  b->inactive_len = carry_offset + bytes_read;
  if (bytes_read == 0) b->eof = true;
}

void swap_buffers(SmarterCSV_Buffer *b) {
  char *tmp = b->active_buf;
  b->active_buf = b->inactive_buf;
  b->inactive_buf = tmp;

  b->length = b->inactive_len;
  b->pos = 0;
}

int next_byte(SmarterCSV_Buffer *b) {
  while (b->pos >= b->length) {
    if (b->eof) return EOF;
    refill_buffer(b);
    if (b->inactive_len == 0) return EOF;
    swap_buffers(b);
  }
  return (unsigned char)b->active_buf[b->pos++];
}

int peek_byte(SmarterCSV_Buffer *b) {
  while (b->pos >= b->length) {
    if (b->eof) return EOF;
    refill_buffer(b);
    if (b->inactive_len == 0) return EOF;
    swap_buffers(b);
  }
  return (unsigned char)b->active_buf[b->pos];
}

static VALUE buffer_alloc(VALUE klass) {
  SmarterCSV_Buffer *b;
  return TypedData_Make_Struct(klass, SmarterCSV_Buffer, &buffer_type, b);
}

static VALUE buffer_initialize(VALUE self, VALUE source, VALUE size_val) {
  SmarterCSV_Buffer *b;
  TypedData_Get_Struct(self, SmarterCSV_Buffer, &buffer_type, b);

  size_t size = NUM2SIZET(size_val);
  if (!init_buffer(b, size)) {
    rb_raise(rb_eRuntimeError, "failed to allocate buffers");
  }

  if (RB_TYPE_P(source, T_STRING)) {
    const char *filename = StringValueCStr(source);
    FILE *fp = fopen(filename, "rb");
    if (!fp) rb_sys_fail("fopen");
    b->fp = fp;
    b->source_type = SOURCE_FILE_PTR;
  } else if (rb_respond_to(source, rb_intern("read"))) {
    b->ruby_io = source;
    b->source_type = SOURCE_RUBY_IO;
    rb_gc_register_address(&b->ruby_io);
  } else {
    rb_raise(rb_eTypeError, "expected String filename or IO object");
  }

  refill_buffer(b);
  if (b->inactive_len > 0) {
    swap_buffers(b);
  } else {
    b->length = 0;
    b->pos = 0;
  }

  return self;
}

static VALUE buffer_next_byte(VALUE self) {
  SmarterCSV_Buffer *b;
  TypedData_Get_Struct(self, SmarterCSV_Buffer, &buffer_type, b);

  int byte = next_byte(b);
  if (byte == EOF) return Qnil;
  char c = (char)byte;
  return rb_str_new(&c, 1);
}

static VALUE buffer_peek_byte(VALUE self) {
  SmarterCSV_Buffer *b;
  TypedData_Get_Struct(self, SmarterCSV_Buffer, &buffer_type, b);

  int byte = peek_byte(b);
  if (byte == EOF) return Qnil;
  char c = (char)byte;
  return rb_str_new(&c, 1);
}

#define SCRATCH_BUFFER_SIZE 4096

static VALUE buffer_peek_bytes(int argc, VALUE *argv, VALUE self) {
  SmarterCSV_Buffer *b;
  TypedData_Get_Struct(self, SmarterCSV_Buffer, &buffer_type, b);

  size_t n = 1;
  if (argc == 1) {
    n = NUM2SIZET(argv[0]);
    if (n == 0) return rb_str_new("", 0);
  }

  size_t available = b->length - b->pos;
  if (n <= available) {
    return rb_str_new(b->active_buf + b->pos, n);
  }

  // allocate scratch buffer
  char *scratch = malloc(n);
  if (!scratch) rb_raise(rb_eNoMemError, "Unable to allocate scratch buffer");

  size_t copied = 0;

  // copy from current active_buf
  if (available > 0) {
    memcpy(scratch, b->active_buf + b->pos, available);
    copied += available;
  }

  // read remaining bytes into temp buffer
  size_t to_fetch = n - copied;
  char *tail = scratch + copied;

  off_t rewind_offset = 0;
  if (b->source_type == SOURCE_FILE_PTR) {
    rewind_offset = ftell(b->fp);
    size_t read = fread(tail, 1, to_fetch, b->fp);
    fseek(b->fp, rewind_offset, SEEK_SET);  // rewind to original position
    copied += read;
  } else if (b->source_type == SOURCE_RUBY_IO) {
    VALUE str = rb_funcall(b->ruby_io, rb_intern("read"), 1, SIZET2NUM(to_fetch));
    if (!NIL_P(str)) {
      memcpy(tail, RSTRING_PTR(str), RSTRING_LEN(str));
      copied += RSTRING_LEN(str);
      rb_funcall(b->ruby_io, rb_intern("seek"), 2, LL2NUM(-((long)RSTRING_LEN(str))), INT2FIX(SEEK_CUR));
    }
  }

  VALUE result = copied == 0 ? Qnil : rb_str_new(scratch, copied);
  free(scratch);
  return result;
}


static VALUE buffer_eof(VALUE self) {
  SmarterCSV_Buffer *b;
  TypedData_Get_Struct(self, SmarterCSV_Buffer, &buffer_type, b);
  return b->eof ? Qtrue : Qfalse;
}

void Init_buffered_io(void) {
  VALUE mSmarterCSV = rb_define_module("SmarterCSV");
  VALUE cBufferedIO = rb_define_class_under(mSmarterCSV, "BufferedIO", rb_cObject);

  rb_define_alloc_func(cBufferedIO, buffer_alloc);
  rb_define_method(cBufferedIO, "initialize", buffer_initialize, 2);
  rb_define_method(cBufferedIO, "next_byte", buffer_next_byte, 0);
  rb_define_method(cBufferedIO, "peek_byte", buffer_peek_byte, 0);
  rb_define_method(cBufferedIO, "peek_bytes", buffer_peek_bytes, -1);
  rb_define_method(cBufferedIO, "eof?", buffer_eof, 0);
}
