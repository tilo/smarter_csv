// ext/smarter_csv/buffered_io.h
#ifndef BUFFERED_IO_H
#define BUFFERED_IO_H

#include "ruby.h"
#include <stdio.h>
#include <stdbool.h>

#define BUFFER_SIZE_256K (256 * 1024)
#define BUFFER_SIZE_512K (512 * 1024)
#define BUFFER_SIZE_1MB   (1024 * 1024)

#define MAX_CARRY_ZONE 4096

typedef enum {
  SOURCE_FILE_PTR,
  SOURCE_RUBY_IO
} BufferedIoSourceType;

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
  BufferedIoSourceType source_type;
  VALUE rb_cEncoding;

  bool eof;
} BufferedIoBufferType;

extern const rb_data_type_t buffer_type;

// Optionally declare these if parser.c or other code needs them:
bool init_buffer(BufferedIoBufferType *b, size_t buffer_size);
void refill_buffer(BufferedIoBufferType *b);
void swap_buffers(BufferedIoBufferType *b);
int next_byte(BufferedIoBufferType *b);
int peek_byte(BufferedIoBufferType *b);
const char *peek_bytes(BufferedIoBufferType *b, size_t n, size_t *available);

#endif // BUFFERED_IO_H
