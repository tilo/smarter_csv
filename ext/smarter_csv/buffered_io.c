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
  bool eof;
} SmarterCSV_Buffer;

static void smarter_csv_buffer_free(void *ptr) {
  SmarterCSV_Buffer *b = (SmarterCSV_Buffer *)ptr;
  if (b) {
    free(b->buffer1);
    free(b->buffer2);
    fclose(b->fp);
    xfree(b);
  }
}

static const rb_data_type_t smarter_csv_buffer_type = {
  "SmarterCSV_Buffer",
  { NULL, smarter_csv_buffer_free, NULL },
  0, 0, RUBY_TYPED_FREE_IMMEDIATELY
};

bool smarter_csv_init_buffer(SmarterCSV_Buffer *b, FILE *fp, size_t buffer_size) {
  b->buffer1 = malloc(buffer_size);
  b->buffer2 = malloc(buffer_size);
  if (!b->buffer1 || !b->buffer2) return false;

  b->active_buf = b->buffer1;
  b->inactive_buf = b->buffer2;
  b->buffer_size = buffer_size;
  b->pos = 0;
  b->length = 0;
  b->carry_len = 0;
  b->inactive_len = 0;
  b->fp = fp;
  b->eof = false;

  smarter_csv_refill_buffer(b);
  smarter_csv_swap_buffers(b);
  return true;
}

void smarter_csv_refill_buffer(SmarterCSV_Buffer *b) {
  size_t carry_offset = 0;

  // Carry over remaining bytes at end of buffer
  if (b->length - b->pos > 0) {
    size_t remaining = b->length - b->pos;
    if (remaining > MAX_CARRY_ZONE) remaining = MAX_CARRY_ZONE;
    memcpy(b->inactive_buf, b->active_buf + b->length - remaining, remaining);
    carry_offset = remaining;
  }

  size_t to_read = b->buffer_size - carry_offset;
  size_t bytes_read = fread(b->inactive_buf + carry_offset, 1, to_read, b->fp);

  b->inactive_len = carry_offset + bytes_read;
  if (bytes_read == 0) b->eof = true;
}

void smarter_csv_swap_buffers(SmarterCSV_Buffer *b) {
  char *tmp = b->active_buf;
  b->active_buf = b->inactive_buf;
  b->inactive_buf = tmp;

  b->length = b->inactive_len;
  b->pos = 0;
}

int smarter_csv_next_byte(SmarterCSV_Buffer *b) {
  if (b->pos >= b->length) {
    if (b->eof) return EOF;
    smarter_csv_swap_buffers(b);
    smarter_csv_refill_buffer(b);
    if (b->length == 0) return EOF;
  }
  return (unsigned char)b->active_buf[b->pos++];
}

static VALUE smarter_csv_buffer_alloc(VALUE klass) {
  SmarterCSV_Buffer *b;
  return TypedData_Make_Struct(klass, SmarterCSV_Buffer, &smarter_csv_buffer_type, b);
}

static VALUE smarter_csv_buffer_initialize(VALUE self, VALUE path, VALUE size_val) {
  SmarterCSV_Buffer *b;
  TypedData_Get_Struct(self, SmarterCSV_Buffer, &smarter_csv_buffer_type, b);

  const char *filename = StringValueCStr(path);
  FILE *fp = fopen(filename, "rb");
  if (!fp) rb_sys_fail("fopen");

  size_t size = NUM2SIZET(size_val);
  if (!smarter_csv_init_buffer(b, fp, size)) {
    fclose(fp);
    rb_raise(rb_eRuntimeError, "failed to allocate buffers");
  }

  return self;
}

static VALUE smarter_csv_buffer_next_byte(VALUE self) {
  SmarterCSV_Buffer *b;
  TypedData_Get_Struct(self, SmarterCSV_Buffer, &smarter_csv_buffer_type, b);

  int byte = smarter_csv_next_byte(b);
  if (byte == EOF) return Qnil;
  char c = (char)byte;
  return rb_str_new(&c, 1);
}

static VALUE smarter_csv_buffer_eof(VALUE self) {
  SmarterCSV_Buffer *b;
  TypedData_Get_Struct(self, SmarterCSV_Buffer, &smarter_csv_buffer_type, b);
  return b->eof ? Qtrue : Qfalse;
}

void Init_smarter_csv_buffered_io(void) {
  VALUE mSmarterCSV = rb_define_module("SmarterCSV");
  VALUE cBufferedIO = rb_define_class_under(mSmarterCSV, "BufferedIO", rb_cObject);

  rb_define_alloc_func(cBufferedIO, smarter_csv_buffer_alloc);
  rb_define_method(cBufferedIO, "initialize", smarter_csv_buffer_initialize, 2);
  rb_define_method(cBufferedIO, "next_byte", smarter_csv_buffer_next_byte, 0);
  rb_define_method(cBufferedIO, "eof?", smarter_csv_buffer_eof, 0);
}
