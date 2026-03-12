# SmarterCSV 1.16.0 — Changes

RSpec tests: **714 → 1,232** (+518 tests)

---

## Breaking Changes

* **New option `quote_boundary:` defaults to `:standard`**: quotes are now only recognized
  as field delimiters at field boundaries; mid-field quotes are treated as literal characters.
  This slightly changes parsing behavior for CSV data and brings it on par with other CSV
  libraries. Use `quote_boundary: :legacy` only in exceptional cases to restore previous
  behavior. See [Parsing Strategy](../../parsing_strategy.md).

---

## Performance Improvements

### C Extension

- **ParseContext architecture**: All per-file parse options are now wrapped in a GC-managed
  `TypedData` object (`parse_context_t`) built once after headers are loaded. Eliminates
  ~10 `rb_hash_aref` calls per row that previously read directly from the options hash on
  every row.
- **Column-filter bitmap**: `_keep_bitmap` precomputed as a packed binary `String` — one
  `memcpy`-style check per row replaces N `rb_ary_entry` calls. Loop invariants
  `_keep_extra_cols` and `_early_exit_after` precomputed once; `_keep_cols=false` sentinel
  skips bitmap logic entirely on files without column selection (one `!= Qfalse` test per row).
- **Section 4 fast-path split**: The C unquoted inner loop is split into two sub-paths —
  plain unquoted vs. boundary-aware `:standard` mode — so the common case avoids all
  quote-boundary state tracking. `__builtin_expect` hints applied to both guards.
- **Section 2 lazy lookups**: `quote_escaping` / `quote_boundary` reads moved from
  unconditional Section 2 (every row) to Section 5 (quoted-field path only).
  `only_headers` / `except_headers` / `strict` lookups guarded by `_keep_cols` nil-check.
  Duplicate `row_sep` lookup removed.
- **Byte-level indexing**: All `line[i]` character lookups inside inner loops replaced with
  `line.getbyte(i)` (returns Integer Fixnum directly, ~5–10 ns, zero allocation vs. ~30–50 ns
  one-char String per call). Field extraction switched to `line.byteslice(start, len)`.
  `col_sep_byte` and `quote_byte` precomputed as integers.
- **Skip-ahead in quoted fields**: `memchr` jump to next quote character instead of advancing
  one byte at a time inside quoted fields.
- **Skip-ahead for unquoted fields in `:standard` mode**: Once a field is confirmed unquoted,
  `String#index` jumps directly to the next `col_sep`, bypassing per-character state checks.
- **Compiler flag `-fno-semantic-interposition`**: Added to `extconf.rb` for GCC/Clang
  (excluded from MSVC). Enables more aggressive LTO inlining and bypasses the PLT for
  intra-library calls on Linux.
- **`cold`/`hot` function attributes + compiler hints**: Applied to rarely-executed paths and
  hot inner loops respectively to guide branch predictor and instruction cache layout.

### Ruby Path

- **Unquoted fast path — direct hash construction**: `parse_line_to_hash_ruby` builds the
  result hash directly from `String#split` for unquoted lines. Eliminates the intermediate
  `Array` from `parse_csv_line_ruby` and a second full-row iteration. Uses integer-index
  `while` loops instead of Ruby enumerators.
- **`byteindex` skip-ahead**: Inside quoted fields, `String#byteindex` (Ruby 3.2+) or inline
  `getbyte` scan jumps to next quote or col_sep at C speed. Falls back correctly on
  JRuby/TruffleRuby.
- **Empty field skipping inline**: `remove_empty_values` now filters empty fields inline
  during hash building rather than post-processing. Combined with `strip_whitespace: true`
  (default), catches both empty and whitespace-only fields without regex.
- **Quoted field extraction**: Content extracted directly with `byteslice` excluding
  surrounding quotes; avoids double allocation. In-place `.strip!` on fresh byteslice avoids
  a second allocation.
- **Backslash detection fast-path**: In `:auto` quote_escaping mode, when the line contains no
  backslash character, skips the backslash-try dance and calls RFC 4180 mode directly.
- **Hot-path option caching**: `@hot_path_options`, `@quote_escaping_backslash`,
  `@quote_escaping_double`, `@delete_nil_keys`, `@delete_empty_keys`, `@quote_char`, and
  `@field_size_limit` precomputed as ivars once after headers are loaded — all per-row
  option-hash lookups replaced by cheap ivar reads.
- **Multiline gate optimization**: `detect_multiline_strict` used as a cheap gate in the
  stitch loop; avoids N-2 full re-parses per multiline row in the Ruby path.

### Net Benchmark Result (C-accelerated, Apple M1, Ruby 3.4.7)

- **2×–8× faster than Ruby `CSV.read`** (which only tokenizes and returns raw arrays; no post-processing)
- **7×–129× faster than `CSV.table`** (nearest equivalent output — symbol keys + numeric conversion)
- **9×–65× faster than SmarterCSV 1.14.4** across all 19 benchmark files
- **up to 2.4× faster than 1.15.2** (15/19 benchmark files faster)

See [performance_notes.md](performance_notes.md) and [benchmarks.md](benchmarks.md).

---

## New Features

### Reader

**New top-level API:**

- **`SmarterCSV.parse(csv_string, options = {})`**: Parse a CSV string directly without
  wrapping in `StringIO`. Drop-in equivalent of `CSV.parse(str, headers: true,
  header_converters: :symbol)` with numeric conversion included. See
  [Migrating from Ruby CSV](../../migrating_from_csv.md).
- **`SmarterCSV.each(input, options = {}, &block)`**: Row-by-row enumerator yielding each
  row as a `Hash`. Returns an `Enumerator` when called without a block.
- **`SmarterCSV.each_chunk(input, options = {}, &block)`**: Chunked enumerator yielding
  `(Array<Hash>, chunk_index)`. Requires `chunk_size` in options. Returns an `Enumerator`
  without a block.

**New `Reader` instance methods:**

- **`Reader#each { |hash| }`**: Yields each row as a `Hash`. `Reader` now includes
  `Enumerable` (enables `map`, `select`, `lazy`, etc.).
- **`Reader#each_chunk { |chunk, index| }`**: Yields each chunk plus 0-based chunk index.

**New options:**

- **`quote_boundary: :standard`** *(default — breaking change)*: Quotes are only recognized
  as field delimiters at field boundaries; mid-field quotes are treated as literal characters.
  Use `quote_boundary: :legacy` to restore previous behavior.
- **`quote_escaping: :auto`** *(default)*: Tries backslash interpretation first; automatically
  downgrades to RFC 4180 when no backslash is present in the line. Also accepts `:backslash`
  and `:double_quotes`.
- **`headers: { only: [...] }`**: Keep only the specified columns in each result hash.
  Excluded columns are skipped in the C hot path — no string allocation, no conversion, no
  hash insertion. See [Column Selection](../../column_selection.md).
- **`headers: { except: [...] }`**: Remove the specified columns from each result hash. Same
  hot-path optimization. Cannot be combined with `headers: { only: }`.
- **`on_bad_row:`**: Controls behavior when a row raises a parse error. Values: `:raise`
  (default), `:skip`, `:collect`, or a callable. With `:collect`, error records accumulate in
  `reader.errors[:bad_rows]`. See [Bad Row Quarantine](../../bad_row_quarantine.md).
- **`bad_row_limit: N`**: Raises `SmarterCSV::TooManyBadRows` after N bad rows. Default: `nil`
  (unlimited).
- **`collect_raw_lines: true`** *(default)*: Include the raw stitched line in bad-row error
  records. Set to `false` for privacy or memory savings.
- **`field_size_limit: N`**: Maximum size of any extracted field in bytes. Raises
  `SmarterCSV::FieldSizeLimitExceeded` if a field or accumulating multiline buffer exceeds
  the limit. Prevents DoS from runaway quoted fields. See
  [Bad Row Quarantine](../../bad_row_quarantine.md#limiting-field-size-field_size_limit).
- **`nil_values_matching: regex`**: Set matching values to `nil` via regular expression. With
  `remove_empty_values: true` (default), nil-ified values are removed. With
  `remove_empty_values: false`, the key is retained with a `nil` value. Replaces deprecated
  `remove_values_matching:`.
- **`missing_headers: :auto`** *(default)*: Auto-generate names for extra columns using
  `missing_header_prefix` (e.g. `column_7`, `column_8`). Use `:raise` to raise
  `HeaderSizeMismatch` instead. Replaces deprecated `strict:`.
- **`verbose: :quiet / :normal / :debug`**: Symbol-based verbosity levels. `:quiet` suppresses
  all output; `:normal` (default) shows behavioral warnings; `:debug` adds computed options and
  per-row diagnostics to `$stderr`. Replaces deprecated `verbose: true/false`.
- **`on_start: callable`**: Fires once before the first row with
  `{ input:, file_size:, col_sep:, row_sep: }`.
- **`on_chunk: callable`**: Fires after each chunk (chunked mode only) with
  `{ chunk_number:, rows_in_chunk:, total_rows_so_far: }`.
- **`on_complete: callable`**: Fires after the file is exhausted with
  `{ total_rows:, total_chunks:, duration:, bad_rows: }`.

See [Instrumentation Hooks](../../instrumentation.md).

**New exceptions:**

- **`SmarterCSV::FieldSizeLimitExceeded`**: Raised when `field_size_limit` is exceeded.
- **`SmarterCSV::TooManyBadRows`**: Raised when `bad_row_limit` is exceeded.

**Deprecations:**

- `only_headers:` → use `headers: { only: }`
- `except_headers:` → use `headers: { except: }`
- `remove_values_matching:` → use `nil_values_matching:`
- `strict: true` → use `missing_headers: :raise`
- `strict: false` → use `missing_headers: :auto`
- `verbose: true` → use `verbose: :debug`
- `verbose: false` → use `verbose: :normal`

### Writer

- **IO and StringIO support**: `SmarterCSV.generate` and `SmarterCSV::Writer.new` now accept
  any `IO`-compatible object (responding to `#write`) in addition to a file path or
  `Pathname`. The caller retains ownership of passed-in IO objects.
- **`SmarterCSV.generate` returns a String when called without a destination**: Omit the file
  argument and the CSV is written to an internal buffer and returned as a `String`. Options
  hash can be passed as the sole argument.
- **Streaming mode for known headers**: When `headers:` or `map_headers:` is provided at
  construction time, the Writer skips the internal temp file entirely — the header line is
  written immediately and each `<<` streams directly to the output file. No API change;
  existing code benefits automatically. See [The Basic Write API](../../basic_write_api.md).
- **`encoding:` option**: Specifies the file encoding (e.g. `'UTF-8'`, `'ISO-8859-1'`).
  Supports Ruby's `'external:internal'` transcoding notation. Only applies when writing to a
  file path; ignored for IO objects.
- **`write_nil_value:` option** *(default: `''`)*: String written in place of `nil` field
  values.
- **`write_empty_value:` option** *(default: `''`)*: String written in place of empty-string
  field values, including missing keys.
- **`write_bom:` option** *(default: `false`)*: Prepends a UTF-8 BOM (`\xEF\xBB\xBF`) to the
  output. Useful for Excel compatibility with non-ASCII content.

---

## Bug Fixes

### Reader

- **Mid-field quotes no longer corrupt unquoted fields**: `quote_boundary: :standard` (now the
  default) prevents a quote character mid-field (e.g. `b"bb`) from toggling quoted state. This
  silently corrupted rows in 1.15.2 when data contained apostrophes or inch marks.
- **Unclosed-quote fallback in `:auto` mode**: When backslash mode encounters an unclosed quote
  at EOL, the parser now tries RFC 4180 mode as a fallback before treating the row as multiline.
- **Empty headers bug fixed** ([#324](https://github.com/tilo/smarter_csv/issues/324),
  [#312](https://github.com/tilo/smarter_csv/issues/312)): CSV files with empty or
  whitespace-only header fields (e.g. `name,,`) now auto-generate column names using
  `missing_header_prefix` (default: `column_1`, `column_2`, …).
- **All library output now goes to `$stderr`**: Behavioral warnings use `warn` (suppressible
  via `-W0` or `verbose: :quiet`); debug diagnostics use `$stderr.puts`. Nothing is written to
  `$stdout`.
- **`SmarterCSV.generate` raises `ArgumentError`** (not a blank `RuntimeError`) when called
  without a block.

### Writer

- **Temp file no longer hardcoded to `/tmp`**: Fixes `Errno::ENOENT` on Windows.
- **Temp file properly cleaned up**: `Tempfile#close!` now used instead of `Tempfile#delete`,
  ensuring the file is both closed and unlinked.
- **`StringIO` handling**: Writing to a `StringIO` no longer attempts to close it on
  `finalize`.

---

## Misc

- **`@mapped_keys` changed from `Array` to `Set`**: O(1) lookup per field instead of O(n)
  scan on the `value_converters` key check.
- **`escape_csv_field` micro-optimizations**: `@escaped_quote_char` precomputed once in
  `initialize`; redundant `.to_s` call removed; row separator appended with `<<` (mutating)
  instead of `+` to save one string allocation per row.
- **`Reader` includes `Enumerable`**: Enables `map`, `select`, `reject`, `lazy`, and other
  Enumerable methods on `Reader#each` results.
- **`DEFAULT_CHUNK_SIZE = 100`**: Constant added; warning emitted when `each_chunk` is called
  without explicit `chunk_size`.
