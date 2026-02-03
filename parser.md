# ParserC: Streaming CSV Parser Implementation

> **Branch:** `buffered-lowlevel-io`
>
> To switch to this branch: `git checkout buffered-lowlevel-io`

## Overview

`SmarterCSV::ParserC` is a streaming CSV parser implemented in C that reads character-by-character from `BufferedIO`. It handles quoting, multi-character separators, comments, and various encodings.

| | |
|---|---|
| **File** | `ext/parser/parser.c` |
| **Lines of Code** | ~900 |
| **Ruby Class** | `SmarterCSV::ParserC` |
| **Depends On** | `SmarterCSV::BufferedIO` |

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Ruby Code                                 │
│              parser.read_row_as_fields                       │
├─────────────────────────────────────────────────────────────┤
│                    ParserC (C)                               │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  parser_read_row_as_fields_c()                      │    │
│  │    └── parser_read_field_c()  (called per field)   │    │
│  │          └── parser_next_char() (called per char)  │    │
│  │                └── next_byte()  (from BufferedIO)  │    │
│  └─────────────────────────────────────────────────────┘    │
├─────────────────────────────────────────────────────────────┤
│                  BufferedIO (C)                              │
│                 next_byte() / peek_byte()                    │
├─────────────────────────────────────────────────────────────┤
│                  File / Ruby IO                              │
└─────────────────────────────────────────────────────────────┘
```

---

## Data Structures

### Parser Struct (`parser_t`)

```c
typedef struct {
  // Row buffer (256KB max)
  char *buf1;
  char *buf2;              // Reserved for overflow (not yet used)
  char *active_buf;
  size_t buffer_pos;

  // Reference to BufferedIO
  VALUE buffered_io;

  // Field tracking (up to 128K fields per row)
  size_t field_starts[MAX_FIELDS];
  size_t field_lengths[MAX_FIELDS];
  size_t field_count;

  // Separator configuration (cached from options)
  long col_sep_len;
  long row_sep_len;
  long quote_char_len;
  long double_quote_char_len;
  long max_sep_len;
  long comment_prefix_len;

  const char *col_sep_ptr;
  const char *row_sep_ptr;
  const char *quote_char_ptr;
  const char *double_quote_char_ptr;
  const char *comment_prefix_ptr;

  // Encoding flags for fast-path detection
  int is_ascii;
  int is_utf8;
  int is_ascii_or_utf8;

  // Line count callback
  VALUE incr_line_count;
  bool has_incr_proc;
} parser_t;
```

### Constants

```c
#define MAX_ROW_BYTES 262144    // 256 KB max row size
#define MAX_FIELDS    131072    // 128K fields per row
```

---

## Core Functions

### Initialization

```c
static VALUE parser_initialize(VALUE self, VALUE source, VALUE options)
```

- Creates `BufferedIO` instance from source (filename or IO object)
- Extracts and caches separator strings (`col_sep`, `row_sep`, `quote_char`)
- Detects encoding and sets fast-path flags (`is_utf8`, `is_ascii`)
- Stores optional `incr_csv_line_count` callback proc

### Reading Characters

```c
static VALUE parser_next_char(VALUE self)
```

Returns the next character as a Ruby String, handling multi-byte encodings.

**Current implementation:**
1. **ASCII fast-path:** If byte < 0x80, return single-byte string
2. **UTF-8 path:** Trial-and-error assembly using `valid_encoding?`
3. **Other encodings:** Same trial-and-error approach

**Flow:**
```
next_byte() → assemble bytes → force_encoding → valid_encoding? → return
     ↑              ↑                  ↑               ↑
   C call    C buffer ops      Ruby method call  Ruby method call
```

### Reading Fields

```c
static VALUE parser_read_field_c(VALUE self)
```

Reads a single field, handling:
- Quoted fields (starts with `quote_char`)
- Escaped quotes (`""` → `"`)
- Unquoted fields
- Field termination (by `col_sep` or `row_sep`)

**Returns:** `[field_ok, field_closed]` array

### Reading Rows

```c
static VALUE parser_read_row_as_fields_c(VALUE self)
```

Reads an entire row and returns an array of field strings.

**Logic:**
1. Check for comment prefix → skip line if matched
2. Loop calling `parser_read_field_c()`
3. After each field, check for `col_sep` or `row_sep`
4. When `row_sep` found, call `flush_row()` to build Ruby array

### Helper Functions

```c
static void append_chars(parser_t *p, const char *bytes, size_t len)
```
Appends bytes to the row buffer.

```c
static void mark_field_start(parser_t *p)
```
Records the start position of a new field.

```c
static void finalize_field(parser_t *p)
```
Records the length of the completed field.

```c
static VALUE flush_row(parser_t *p, VALUE self)
```
Converts buffer contents into Ruby array of strings with proper encoding.

---

## Ruby API

```ruby
parser = SmarterCSV::ParserC.new(source, {
  col_sep: ",",
  row_sep: "\n",
  quote_char: '"',
  comment_prefix: "#",           # Optional
  buffer_size: 131072,           # Optional, default 128KB
  incr_csv_line_count: -> { }    # Optional callback
})

# Read a single row as array of strings
fields = parser.read_row_as_fields  # => ["field1", "field2", "field3"]

# Read raw row (including row_sep)
line = parser.read_row              # => "field1,field2,field3\n"

# Skip rows
parser.skip_rows(5)

# Check for end of file
parser.eof?                         # => true/false

# Low-level character access
char = parser.next_char             # => "a" or "💡" or nil
chars = parser.peek_chars(3)        # => "abc" (without consuming)
```

---

## Current Encoding Handling

### The Problem

The current `parser_next_char()` uses a trial-and-error approach for multi-byte characters:

```c
// Current implementation (inefficient)
char buf[8];
buf[0] = c;
for (int len = 1; len < 8; ++len) {
  int b2 = next_byte(buffered_io_p);
  buf[len] = (char)b2;

  VALUE str = rb_str_new(buf, len + 1);
  rb_funcall(str, rb_intern("force_encoding"), 1, encoding);      // Ruby call!
  if (RTEST(rb_funcall(str, rb_intern("valid_encoding?"), 0))) {  // Ruby call!
    return str;
  }
}
```

**Issues:**
- 2-8 Ruby method calls per non-ASCII character
- Creates temporary Ruby String objects that are discarded
- Defeats the purpose of using C for performance

### Fast-Path Flags

The parser detects encoding at initialization:

```c
const char *enc_name = RSTRING_PTR(rb_funcall(encoding, rb_intern("to_s"), 0));
p->is_ascii = strcmp(enc_name, "US-ASCII") == 0;
p->is_utf8 = strcmp(enc_name, "UTF-8") == 0;
p->is_ascii_or_utf8 = (p->is_ascii || p->is_utf8);
```

This allows fast-path handling for the common cases.

---

## Improved Implementation Using rb_enc_precise_mbclen

### Overview

Ruby's C API provides `rb_enc_precise_mbclen()` which determines character length for ANY encoding without trial-and-error.

### Required Changes

#### Change 1: Add Include

```c
// At top of parser.c
#include "ruby.h"
#include "ruby/encoding.h"  // ADD THIS
#include <string.h>
```

#### Change 2: Add Encoding Pointer to Struct

```c
typedef struct {
  // ... existing fields ...

  int is_ascii;
  int is_utf8;
  int is_ascii_or_utf8;

  rb_encoding *enc;  // ADD THIS - cached encoding pointer

  VALUE incr_line_count;
  bool has_incr_proc;
} parser_t;
```

#### Change 3: Cache Encoding in Initialize

```c
// In parser_initialize(), after setting is_utf8 flags:
p->enc = rb_enc_get(encoding);
```

#### Change 4: Add UTF-8 Helper Function

```c
// Add before parser_next_char()
static inline int utf8_char_length(unsigned char c) {
  if (c < 0x80) return 1;              // 0xxxxxxx - ASCII
  if ((c & 0xE0) == 0xC0) return 2;    // 110xxxxx
  if ((c & 0xF0) == 0xE0) return 3;    // 1110xxxx
  if ((c & 0xF8) == 0xF0) return 4;    // 11110xxx
  return 1;  // Invalid, treat as single byte
}
```

#### Change 5: Replace parser_next_char()

```c
static VALUE parser_next_char(VALUE self) {
  parser_t *p;
  TypedData_Get_Struct(self, parser_t, &parser_type, p);
  BufferedIoBufferType *buffered_io_p;
  TypedData_Get_Struct(p->buffered_io, BufferedIoBufferType, &buffer_type, buffered_io_p);

  int b = next_byte(buffered_io_p);
  if (b == -1) return Qnil;

  unsigned char c = (unsigned char)b;

  // 1. ASCII fast-path (works for all ASCII-compatible encodings)
  if (c < 0x80) {
    char buf[1] = {(char)c};
    return rb_enc_str_new(buf, 1, p->enc);
  }

  // 2. UTF-8 optimized path (no Ruby calls needed)
  if (p->is_utf8) {
    int len = utf8_char_length(c);
    char buf[4];
    buf[0] = (char)c;
    for (int i = 1; i < len; i++) {
      int b2 = next_byte(buffered_io_p);
      if (b2 == -1) return Qnil;
      buf[i] = (char)b2;
    }
    return rb_enc_str_new(buf, len, p->enc);
  }

  // 3. All other encodings: use rb_enc_precise_mbclen
  char buf[16];
  buf[0] = (char)c;
  int collected = 1;

  while (collected < 16) {
    // Check if we have a complete character
    int charlen = rb_enc_precise_mbclen(buf, buf + collected, p->enc);

    if (MBCLEN_CHARFOUND_P(charlen)) {
      // Complete character found
      return rb_enc_str_new(buf, MBCLEN_CHARFOUND_LEN(charlen), p->enc);
    }

    if (MBCLEN_INVALID_P(charlen)) {
      // Invalid sequence
      return Qnil;
    }

    // MBCLEN_NEEDMORE_P - need more bytes
    int b2 = next_byte(buffered_io_p);
    if (b2 == -1) return Qnil;
    buf[collected++] = (char)b2;
  }

  return Qnil;  // Couldn't form valid character
}
```

### rb_enc_precise_mbclen Return Values

The function returns an encoded integer:

```c
int charlen = rb_enc_precise_mbclen(ptr, end, enc);

// Check result:
if (MBCLEN_CHARFOUND_P(charlen)) {
  // Valid character found
  int len = MBCLEN_CHARFOUND_LEN(charlen);  // Actual byte length
}
else if (MBCLEN_NEEDMORE_P(charlen)) {
  // Need more bytes to determine
  int needed = MBCLEN_NEEDMORE_LEN(charlen);  // How many more
}
else if (MBCLEN_INVALID_P(charlen)) {
  // Invalid byte sequence for this encoding
}
```

### Summary of Changes

| File | Change | Lines |
|------|--------|-------|
| `parser.c` | Add `#include "ruby/encoding.h"` | 1 |
| `parser.c` | Add `rb_encoding *enc` to struct | 1 |
| `parser.c` | Cache encoding in initialize | 1 |
| `parser.c` | Add `utf8_char_length()` helper | 7 |
| `parser.c` | Replace `parser_next_char()` | ~45 |
| **Total** | | **~55 lines** |

### Performance Comparison

| Metric | Current | After Change |
|--------|---------|--------------|
| Ruby calls per ASCII char | 0 | 0 |
| Ruby calls per UTF-8 char | 2-8 | 0 |
| Ruby calls per Shift_JIS char | 2-128 | 1 |
| Temporary Ruby objects | Multiple | 0 |

### Encoding Support After Change

| Encoding | Method Used | Performance |
|----------|-------------|-------------|
| ASCII | Direct (c < 0x80) | Fastest |
| UTF-8 | `utf8_char_length()` | Fast |
| Shift_JIS | `rb_enc_precise_mbclen()` | Good |
| GBK | `rb_enc_precise_mbclen()` | Good |
| EUC-JP | `rb_enc_precise_mbclen()` | Good |
| ISO-8859-x | Direct (single-byte) | Fastest |

---

## Test Files

| File | Description |
|------|-------------|
| `spec/smarter_csv/parserc_spec.rb` | Basic ParserC tests |
| `spec/smarter_csv/parser2_spec.rb` | Comprehensive parser tests |

### Running Parser Tests

```bash
bundle exec rspec spec/smarter_csv/parserc_spec.rb \
                  spec/smarter_csv/parser2_spec.rb
```

---

## Known Issues

1. **Emoji separators** - Tests with emoji `quote_char` are commented out as failing
2. **Encoding name comparison** - Uses exact string match, may miss case variations
3. **Buffer overflow** - No graceful handling if row exceeds 256KB
4. **Compiler warnings** - Several unused variable warnings

---

## Future Improvements

| Improvement | Effort | Impact |
|-------------|--------|--------|
| Implement `rb_enc_precise_mbclen` optimization | Low | High |
| Fix emoji separator handling | Medium | Medium |
| Add row size limit configuration | Low | Low |
| Clean up compiler warnings | Low | Low |
| Add validation for continuation bytes in UTF-8 | Low | Medium |
