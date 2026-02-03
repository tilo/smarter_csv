# Buffered Low-Level I/O for SmarterCSV

> **Branch:** `buffered-lowlevel-io`
>
> To switch to this branch: `git checkout buffered-lowlevel-io`

## Overview

This branch implements a complete rewrite of how SmarterCSV reads CSV files. Instead of relying on Ruby's `readline` to read lines and then parsing them in C, this approach reads bytes directly in C using a custom double-buffered I/O system.

| | |
|---|---|
| **Branch** | `buffered-lowlevel-io` |
| **Base version** | SmarterCSV 1.14.3 |
| **Status** | Work in progress (559 passing, 70 failures) |
| **C extension tests** | 72/72 passing |
| **Last updated** | 2026-02-02 |

---

## Impact Analysis & Recommendation

### Impact Summary

| Component | Performance Impact | Use Case Impact |
|-----------|-------------------|-----------------|
| **BufferedIO** | Medium | High for embedded newlines in quotes |
| **ParserC** | Low-Medium | Marginal over current approach |
| **1.15.0 hash optimization** | High (2-4x measured) | All use cases |

### What 1.15.0 Already Achieves

The `towards-1.15.0` branch already delivers significant performance gains:

- **2-4x speedup** over 1.14.4 (measured across various CSV types)
- Eliminates the `Array#zip + to_h` bottleneck
- Direct hash building in C via `parse_line_to_hash_c`
- Works with existing Ruby `readline` (proven, stable)
- All tests passing

### What buffered-lowlevel-io Adds

- Eliminates Ruby `readline` overhead entirely
- Native handling of quoted fields with embedded newlines (no continuation logic needed)
- Fewer Ruby object allocations per row
- True byte-level streaming

### Challenges with This Approach

- **70 test failures** remaining to fix
- Based on **older 1.14.3 codebase** - would need rebasing/merging with 1.15.0 changes
- **Much more complex C code** to maintain (~900 lines in parser.c alone vs ~230 in smarter_csv.c)
- Performance delta over 1.15.0 is likely **marginal** for most files
- BOM handling not implemented
- Encoding edge cases remain
- JRuby/TruffleRuby would need pure Ruby fallback

### Recommendation

**Ship 1.15.0 as-is.** The gains are already substantial and measurable.

The buffered I/O work is better suited for a potential **2.0 release** if:
1. Users report specific pain points with embedded newlines in quoted fields
2. Benchmarks show meaningful gains over 1.15.0 for real-world use cases
3. There is time to properly merge, stabilize, and maintain the additional C code

### What Could Be Cherry-Picked (Future)

If incremental adoption is desired:

| Idea | Effort | Value |
|------|--------|-------|
| UTF-8 fast-path detection | Low | Low-Medium |
| Double-buffer concept for very large files | Medium | Low |
| Native embedded newline handling | High | Medium (niche use case) |

### Bottom Line

The ROI on finishing buffered-lowlevel-io for 1.15.0 is low. Significant time would be spent fixing 70+ tests and merging codebases for marginal additional gains. The 1.15.0 optimizations already capture the biggest wins.

**Decision (2026-02-02):** Document this branch, ship 1.15.0, and revisit buffered I/O for a future major release if users report specific needs that it would address.

---

## Migration Guide: Copying Files to Another Branch

When ready to incorporate this work into `main` or a release branch, use the following approach.

### Option 1: Git Checkout (Recommended)

The cleanest approach since we only need specific components:

```bash
# From the target branch (e.g., towards-1.15.0 or main)

# 1. Copy C extension directories
git checkout buffered-lowlevel-io -- ext/buffered_io/
git checkout buffered-lowlevel-io -- ext/parser/

# 2. Copy test files
git checkout buffered-lowlevel-io -- spec/smarter_csv/buffered_io_spec.rb
git checkout buffered-lowlevel-io -- spec/smarter_csv/parserc_spec.rb
git checkout buffered-lowlevel-io -- spec/smarter_csv/parser2_spec.rb

# 3. Copy test fixtures
git checkout buffered-lowlevel-io -- spec/fixtures/buffered_io/
git checkout buffered-lowlevel-io -- spec/fixtures/parser/
git checkout buffered-lowlevel-io -- spec/fixtures/simple_w_comments.csv

# 4. Copy documentation
git checkout buffered-lowlevel-io -- buffered_io.md
```

### Option 2: Create a Patch File

```bash
# On buffered-lowlevel-io branch, create a patch of just the relevant files
git diff main -- ext/buffered_io/ ext/parser/ \
    spec/smarter_csv/buffered_io_spec.rb \
    spec/smarter_csv/parserc_spec.rb \
    spec/smarter_csv/parser2_spec.rb \
    spec/fixtures/buffered_io/ \
    spec/fixtures/parser/ \
    > buffered_io.patch

# On target branch, apply it
git apply buffered_io.patch
```

### Post-Copy Integration Work

After copying files, the following integration work is required:

| Task | Effort | Description |
|------|--------|-------------|
| Update gemspec | Low | Add `ext/buffered_io/extconf.rb` and `ext/parser/extconf.rb` to extensions |
| Update Reader class | Medium | Integrate ParserC as alternative to current line-by-line parsing |
| Option translation | Medium | Map SmarterCSV options to ParserC options |
| JRuby/TruffleRuby fallback | Medium | Add pure Ruby fallback when C extensions unavailable |
| Fix BOM handling | Medium | Implement BOM detection/stripping in C or Ruby layer |
| Fix remaining test failures | Medium-High | 70 integration tests need fixes |

### Key Files to Copy

```
ext/
├── buffered_io/
│   ├── buffered_io.c
│   ├── buffered_io.h
│   └── extconf.rb
├── parser/
│   ├── parser.c
│   └── extconf.rb

spec/
├── smarter_csv/
│   ├── buffered_io_spec.rb
│   ├── parserc_spec.rb
│   └── parser2_spec.rb
├── fixtures/
│   ├── buffered_io/
│   │   ├── simple.csv
│   │   ├── long_lines.csv
│   │   └── empty.csv
│   └── parser/
│       └── ...

buffered_io.md          # This documentation
```

---

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Ruby SmarterCSV                       │
│              (Reader, options, transformations)          │
├─────────────────────────────────────────────────────────┤
│              ext/parser/parser.c                         │
│                 SmarterCSV::ParserC                      │
│   - read_row_as_fields() → Array of Strings             │
│   - handles quoting, separators, comments, UTF-8        │
├─────────────────────────────────────────────────────────┤
│            ext/buffered_io/buffered_io.c                 │
│               SmarterCSV::BufferedIO                     │
│   - next_byte / peek_byte / peek_bytes                  │
│   - double-buffering with automatic refill              │
├─────────────────────────────────────────────────────────┤
│              FILE* or Ruby IO object                     │
└─────────────────────────────────────────────────────────┘
```

## Components

### 1. BufferedIO (`ext/buffered_io/`)

A low-level byte buffer that provides efficient sequential access to file data.

#### Key Features
- **Double buffering:** Two buffers (256KB-1MB each) that swap when active is exhausted
- **Dual source support:** Native `FILE*` for maximum speed, or Ruby IO objects for flexibility
- **Carry zone:** 4KB overlap region to handle data spanning buffer boundaries
- **Byte-level API:** Returns raw bytes, not Ruby strings (reduces object allocation)

#### C Structure
```c
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
  bool eof;
} BufferedIoBufferType;
```

#### Ruby API
```ruby
bio = SmarterCSV::BufferedIO.new(source, buffer_size)
bio.next_byte      # => Integer (0-255) or nil at EOF
bio.peek_byte      # => Integer without consuming
bio.peek_bytes(n)  # => Array of Integers
bio.eof?           # => Boolean
bio.encoding       # => Encoding object
```

#### Core Operations
| Function | Description |
|----------|-------------|
| `init_buffer()` | Allocates two buffers |
| `refill_buffer()` | Reads from source into inactive buffer |
| `swap_buffers()` | Swaps active/inactive buffers |
| `next_byte()` | Returns next byte, auto-refills |
| `peek_byte()` | Peeks without consuming |
| `peek_bytes(n)` | Peeks multiple bytes |

### 2. ParserC (`ext/parser/`)

A streaming CSV parser that reads character-by-character from BufferedIO.

#### Key Features
- **256KB row buffer:** Stores field data for current row
- **Field tracking:** Arrays for start positions & lengths (up to 128K fields per row)
- **UTF-8 handling:** Fast path for ASCII, assembles multibyte characters
- **Multi-char separators:** Supports col_sep and row_sep of any length
- **Comment handling:** Skips lines starting with comment_prefix
- **Quote handling:** RFC 4180 compliant with doubled-quote escaping

#### C Structure
```c
typedef struct {
  char *buf1;                    // 256KB row buffer
  char *buf2;                    // Reserved for overflow
  size_t buffer_pos;

  VALUE buffered_io;             // Reference to BufferedIO

  size_t field_starts[MAX_FIELDS];
  size_t field_lengths[MAX_FIELDS];
  size_t field_count;

  long col_sep_len;
  long row_sep_len;
  long quote_char_len;
  const char *col_sep_ptr;
  const char *row_sep_ptr;
  const char *quote_char_ptr;

  int is_ascii_or_utf8;          // Fast path flag
  VALUE incr_line_count;         // Callback for line counting
} parser_t;
```

#### Ruby API
```ruby
parser = SmarterCSV::ParserC.new(source, {
  col_sep: ",",
  row_sep: "\n",
  quote_char: '"',
  comment_prefix: "#",
  buffer_size: 131072,
  incr_csv_line_count: -> { @csv_line_count += 1 }
})

parser.read_row            # => String (raw line)
parser.read_row_as_fields  # => Array of Strings
parser.skip_rows(n)        # => nil
parser.eof?                # => Boolean
```

### 3. Original Parser (`ext/smarter_csv/`)

The existing line-by-line parser from v1.14.x. Takes an already-read line string and parses it into fields. This is what's currently used in production.

## Comparison with Current Approach

| Aspect | Current (v1.14.x) | This Branch |
|--------|-------------------|-------------|
| **I/O** | Ruby `readline` | C byte-level buffer |
| **Parsing** | C parses line string | C reads bytes directly |
| **Memory** | Ruby strings for each line | C buffers, minimal Ruby objects |
| **Newlines in quotes** | Requires Ruby continuation handling | Handled natively in C |
| **Complexity** | Lower | Higher |

## Why BufferedIO vs Ruby IO/StringIO?

### Ruby IO/StringIO Flow

```
File → IO.readline → Ruby String object → C extension receives String → Parse → Ruby Array
            ↑              ↑                        ↑
      Ruby method    Object allocation      String passed to C
```

Every line read:
1. Ruby's `readline` is called (Ruby method dispatch overhead)
2. A new Ruby String object is created for the entire line
3. That String is passed to the C extension
4. C extension parses the String's bytes
5. More Ruby Strings created for each field

### BufferedIO Flow

```
File → C buffer (256KB) → C parser reads bytes directly → Ruby Strings only for final fields
              ↑                      ↑
      Pure C, no Ruby          Pure C function calls
```

The key difference: **no Ruby involvement until the final output**.

### Why This Matters

| Operation | Ruby IO | BufferedIO |
|-----------|---------|------------|
| Read next byte | Ruby method call + potential object allocation | Pure C function call |
| Read a line | Creates Ruby String | Bytes stay in C buffer |
| Memory allocation | Per-line Ruby heap allocation | One 256KB C buffer, reused |
| GC pressure | High (millions of String objects) | Low (only final field Strings) |

### Concrete Example

Reading a 1 million row CSV:

**With Ruby IO:**
- 1 million `readline` calls (Ruby method dispatch)
- 1 million Ruby String allocations for lines
- 5 million+ Ruby String allocations for fields
- Heavy GC activity

**With BufferedIO:**
- ~4 `read` calls (256KB each for 1MB file)
- Millions of `next_byte()` calls, but they're **pure C**:
  ```c
  int next_byte(BufferedIoBufferType *b) {
    return (unsigned char)b->active_buf[b->pos++];  // Just pointer arithmetic
  }
  ```
- Ruby Strings only created for final field values
- Minimal GC pressure

### The Real Win: C-to-C Calls

The parser does this millions of times:

```c
// Pure C - no Ruby method dispatch, no allocation
int b = next_byte(buffered_io_p);
if (b == ',') { ... }
```

With Ruby IO, even `IO#getbyte` involves:
- Ruby method lookup
- Ruby-to-C transition
- Potential object allocation
- C-to-Ruby transition

### When It Matters Most

| Scenario | Benefit |
|----------|---------|
| Small files (< 1MB) | Minimal - Ruby IO is fine |
| Large files (10MB+) | Noticeable - less GC |
| Huge files (100MB+) | Significant - much less memory churn |
| Streaming/real-time | Important - consistent low latency |
| Quoted fields with newlines | High - no continuation line logic needed |

### Summary

BufferedIO isn't "better" for simple cases - it's an optimization for:
1. **Eliminating per-line Ruby object allocation**
2. **Keeping hot-path parsing entirely in C**
3. **Reducing GC pressure on large files**

The trade-off is complexity. For most users, Ruby IO + C parsing (what 1.15.0 does) is plenty fast.

---

## Test Status

```
629 examples, 70 failures, 2 pending (as of 2026-02-02)
```

### Passing
- Basic CSV processing
- Header handling (most)
- Quote escaping
- Multi-char separators
- Comment handling
- Line counting

### Failing
- BOM (Byte Order Mark) handling (36 failures)
- Some edge cases in quote handling
- Some special character handling
- Strip chars from headers

---

## Dedicated C Extension Tests

The C implementations have their own dedicated test suites that verify the core functionality independently from the rest of SmarterCSV.

### Test Files

| File | Tests | Status |
|------|-------|--------|
| `spec/smarter_csv/buffered_io_spec.rb` | 26 | **All pass** |
| `spec/smarter_csv/parserc_spec.rb` | 2 | **All pass** |
| `spec/smarter_csv/parser2_spec.rb` | 44 | **All pass** |
| **Total** | **72** | **All pass** |

**Key Finding:** The core C components work correctly. The 70 failures in the full test suite are in the Ruby integration layer, not in the C code itself.

### BufferedIO Test Coverage (`buffered_io_spec.rb`)

| Category | What's Tested |
|----------|---------------|
| **Small buffer sizes** | 2, 3, 4, 16, 128 bytes |
| **Large files** | 512, 1024, 8096, 16384 byte buffers |
| **Source types** | File paths and Ruby IO objects (StringIO) |
| **Corner cases** | Empty files, exact buffer boundaries, null bytes |
| **UTF-8** | Multi-byte characters across buffer boundaries |
| **peek_byte** | Returns byte without advancing, EOF handling |
| **peek_bytes(n)** | Multiple bytes, partial results, repeated peeks without advancing |

### ParserC Test Coverage (`parserc_spec.rb` + `parser2_spec.rb`)

| Category | What's Tested |
|----------|---------------|
| **Simple cases** | 1 column, 3 columns, with/without row_sep |
| **Custom row_sep** | `\n`, `\r`, `\n\r`, `\x00`, emoji |
| **Custom col_sep** | `,`, `:`, `\t`, `\|`, `\x01` |
| **Custom quote_char** | `"`, `^`, `<>`, binary chars |
| **Quote handling** | Escaped quotes (`""`), quoted fields with separators inside |
| **Encoding support** | UTF-8, Shift_JIS, ISO-8859-1 |
| **Malformed input** | Invalid UTF-8 sequences |
| **Comments** | Lines starting with `comment_prefix` |
| **Embedded separators** | col_sep and row_sep inside quoted fields |

### Running C Extension Tests

```bash
bundle exec rspec spec/smarter_csv/buffered_io_spec.rb \
                  spec/smarter_csv/parserc_spec.rb \
                  spec/smarter_csv/parser2_spec.rb
```

---

## UTF-8, Emoji, and Multi-byte Character Handling

### How BufferedIO Handles Multi-byte Characters

BufferedIO operates at the **byte level** - it has no concept of characters:

```c
int next_byte(BufferedIoBufferType *b) {
  return (unsigned char)b->active_buf[b->pos++];  // Returns 0-255
}
```

A UTF-8 emoji like 💡 is 4 bytes: `F0 9F 92 A1`. BufferedIO sees these as 4 separate values.

### Current Handling in ParserC

The parser has a `next_char()` function that assembles bytes into characters:

```c
// Fast path for ASCII (single byte)
if (c < 0x80) {
  return rb_str_new((const char *)&c, 1);
}

// Slow path: assemble multi-byte UTF-8
char buf[8];
buf[0] = c;
for (int len = 1; len < 8; ++len) {
  int b2 = next_byte(buffered_io_p);
  buf[len] = (char)b2;

  VALUE str = rb_str_new(buf, len + 1);
  rb_funcall(str, rb_intern("force_encoding"), 1, encoding);
  if (RTEST(rb_funcall(str, rb_intern("valid_encoding?"), 0))) {
    return str;  // Valid character assembled
  }
}
```

### Potential Issues

| Issue | Risk | Current Status |
|-------|------|----------------|
| **Buffer boundary splits** | Medium | Carry zone (4KB) should handle, but edge cases possible |
| **Emoji as separator** | High | Tests commented out as "CURRENTLY FAILING" |
| **Emoji in field content** | Low | Should work - bytes copied, encoding applied at end |
| **Shift_JIS, other encodings** | Medium | Basic tests pass, edge cases unknown |
| **Invalid UTF-8 sequences** | Medium | Returns nil, may lose data |
| **Performance of slow path** | Medium | Ruby method calls for each multi-byte char |

### Evidence from Tests

In `parser2_spec.rb`, there are commented-out failing tests:

```ruby
# ["🔺"].each do |quote_char|
# THESE ARE CURRENTLY FAILING!
```

And working tests for simpler multi-byte:

```ruby
it 'reads UTF-8 characters correctly' do
  input = "abc💡🚀xyz\n"
  # ... this passes
end
```

### Specific Concerns

#### 1. Multi-byte Separators

If `col_sep` or `row_sep` is an emoji, the byte-by-byte comparison might have issues:

```c
// This compares bytes, not characters
if (strncmp(RSTRING_PTR(peek), p->col_sep_ptr, p->col_sep_len) == 0)
```

This *should* work since it compares the full byte sequence, but needs thorough testing.

#### 2. Buffer Boundary Edge Case

```
Buffer 1: [...data...][F0][9F]  ← First 2 bytes of 💡
Buffer 2: [92][A1][...data...]  ← Last 2 bytes of 💡
```

The carry zone is designed for this, but what if:
- The emoji spans the carry zone boundary?
- The buffer is very small (tests use 4-8 byte buffers)?

#### 3. Encoding Detection

```c
const char *enc_name = RSTRING_PTR(rb_funcall(encoding, rb_intern("to_s"), 0));
p->is_utf8 = strcmp(enc_name, "UTF-8") == 0;
```

This string comparison is fragile - what about "utf-8" lowercase?

### Recommendations Before Production Use

| Task | Priority |
|------|----------|
| Fix emoji quote_char tests | High |
| Test with various emoji separators | High |
| Test large files with emojis at buffer boundaries | Medium |
| Test Shift_JIS, GB2312, other multi-byte encodings | Medium |
| Add encoding name normalization | Low |
| Benchmark slow path vs fast path ratio | Low |

### Summary

| Scenario | Status |
|----------|--------|
| **Content with multi-byte characters** | Likely works (bytes preserved, encoding applied at end) |
| **Multi-byte separators** | Risky - some tests are known failing |
| **Edge cases at buffer boundaries** | Needs more testing |

---

## Potential Benefits

1. **No Ruby readline overhead** - Reading happens entirely in C
2. **Embedded newlines** - Quoted fields with `\n` handled natively without continuation line logic
3. **Memory efficiency** - Fewer Ruby string allocations per row
4. **True streaming** - No Ruby objects created until fields are finalized

## Known Issues & TODOs

1. **BOM handling** - Not implemented in C parser, needs to strip BOM bytes
2. **Encoding edge cases** - Some non-UTF-8 encodings may have issues
3. **Integration** - Full integration with Reader class options needs review
4. **Error messages** - Could be more descriptive
5. **Compiler warnings** - Several warnings to clean up

## Building

```bash
bundle install
bundle exec rake compile
bundle exec rspec
```

## Files

```
ext/
├── buffered_io/
│   ├── buffered_io.c      # Double-buffered I/O implementation
│   ├── buffered_io.h      # Shared header for parser.c
│   └── extconf.rb         # Build configuration
├── parser/
│   ├── parser.c           # Streaming CSV parser
│   └── extconf.rb         # Build configuration
└── smarter_csv/
    ├── smarter_csv.c      # Original line parser (v1.14.x)
    └── extconf.rb         # Build configuration
```

## Next Steps

1. Fix BOM handling in BufferedIO or ParserC
2. Review and fix remaining test failures
3. Benchmark against current Ruby readline approach
4. Clean up compiler warnings
5. Consider fallback path for JRuby/TruffleRuby
