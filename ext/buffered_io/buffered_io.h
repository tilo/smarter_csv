// ext/smarter_csv/buffered_io.h
#ifndef SMARTERCSV_BUFFER_H
#define SMARTERCSV_BUFFER_H

#include "ruby.h"
#include <stdio.h>
#include <stdbool.h>

#define BUFFER_SIZE_256K (256 * 1024)
#define BUFFER_SIZE_512K (512 * 1024)
#define BUFFER_SIZE_1MB   (1024 * 1024)

#define MAX_CARRY_ZONE 16

typedef enum {
  SOURCE_FILE_PTR,
  SOURCE_RUBY_IO
} SmarterCSV_SourceType;

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
  VALUE rb_cEncoding;

  bool eof;
} SmarterCSV_Buffer;

extern const rb_data_type_t buffer_type;

// Optionally declare these if parser.c or other code needs them:
bool init_buffer(SmarterCSV_Buffer *b, size_t buffer_size);
void refill_buffer(SmarterCSV_Buffer *b);
void swap_buffers(SmarterCSV_Buffer *b);
int next_byte(SmarterCSV_Buffer *b);
int peek_byte(SmarterCSV_Buffer *b);

#endif // SMARTERCSV_BUFFER_H
