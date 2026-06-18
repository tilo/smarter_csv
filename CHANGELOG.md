
# SmarterCSV 1.x Change Log

> [!TIP]
> **Upgrading?** The [SmarterCSV Upgrade Wizard](https://tilo.github.io/smarter_csv/upgrade_wizard.html) walks you through what (if anything) you need to change for your specific version. Most steps do not require any changes.

## 1.17.5 (2026-06-17)

### Performance

  - SIMD scanner for backslash-escaped quoted fields (C-path), using NEON (arm64) and SSE2 (x86-64) with a scalar fallback. Speeds up `quote_escaping: :backslash` parsing of long quoted fields.

  | File                       | C-path                           |
  |----------------------------|----------------------------------|
  | backslash_long_fields_60k  | 1.45× faster (0.1825s → 0.1256s) |

### Improvements

  - Improved robustness of symbol-valued enum option processing.

### Tests

  - added parity tests for long quoted-field scanning across 16-byte boundaries, running on both the C and Ruby paths.
  - added tests for string-to-symbol coercion of the enum options.



## 1.17.4 (2026-06-03)

### Bug Fix

  - fixed [Issue #337](https://github.com/tilo/smarter_csv/issues/337): `Pathname` input no longer worked (regression since 1.17.0); passing a `Pathname` raised `NoMethodError: private method 'gets' called`. `SmarterCSV` now opens any path-like input (`String` or `Pathname`) and reads directly from any already-open IO. Thanks to [Alex Shenia](https://github.com/alexshenia)



## 1.17.3 (2026-05-26)

RSpec tests: **2,274→ 2,277** (+3 tests)

* No functional changes
* added 3 test cases

### Improvements
* DRY-up C-code
* no performance changes on the C-path

### Performance
* performance improvement on the Ruby-path

  | File                              | RB-path      |
  |-----------------------------------|--------------|
  | PEOPLE_IMPORT_B / PEOPLE_IMPORT_C | 13.5% faster |
  | tab_separated_60k                 | 13.2% faster |
  | sample_100k                       | 10.3% faster |
  | multi_char_separator              | 9.0% faster  |
  | utf8_multibyte                    | 7.1% faster  |
  | many_empty_fields                 | 6.7% faster  |
  | PEOPLE_IMPORT_NC                  | 5.2% faster  |
  | sensor_data                       | 4.5% faster  |


## 1.17.2 (2026-05-21)

RSpec tests: **2,220→ 2,274** (+54 tests)

### Bug Fixes

  - fixed [Issue #334](https://github.com/tilo/smarter_csv/issues/334) with escaped double quote followed by comma. Thanks to [conorg](https://github.com/conorg)
  - fixed bug when using `headers: { except: }`
  - added more tests

## 1.17.1 (2026-05-17)

RSpec tests: **2,210→ 2,220** (+10 tests)

### Bug Fix

  - fixing issue with `remove_empty_hashes: false` not being honored in accelerated path (does not affect you when you use default settings)

## 1.17.0 (2026-05-14)

RSpec tests: **1,434 → 2,210** (+776 tests)

### New Features

* **Streaming IO support** — SmarterCSV now works with non-seekable IO sources such as pipes, STDIN, and Zlib streams.
  A rewindable peek buffer transparently captures the first bytes of the stream so that `row_sep` and `col_sep` auto-detection can replay them without requiring the underlying source to support `rewind` or `seek`.

* **Structured warnings** — auto-detection and configuration warnings are now collected on the Reader as a deduped histogram:

  ```ruby
  reader = SmarterCSV::Reader.new('data.csv')
  reader.process
  reader.warnings  # => [{ type:, code:, severity:, message:, count: }, ...]
  ```

  Repeated warnings of the same `(type, code)` are deduped — `count` tracks occurrences. Available codes today: `:chunk_size_default`, `:header_a_method`, `:utf8_missing_binary_mode`, `:no_clear_row_sep`, `:no_row_sep_found`.

* **Class-level `SmarterCSV.warnings`** accessor — mirrors `SmarterCSV.errors`. Per-thread, cleared at the start of each `.process` / `.parse` / `.each` / `.each_chunk` call. Safe under Puma/Sidekiq.

* **Rails.logger routing** — when `Rails.logger` is present, warnings are routed through it at the severity declared at the call site (`:debug` / `:info` / `:warn` / `:error` / `:fatal`); otherwise `Kernel#warn` is used as a fallback. Detection is cached at construct time, no per-call overhead.

### Improvements

* Improved auto-detection of `row_sep` and `col_sep` — giving more accurate results on files with comment headers.

* Larger scan window for accurate row separator detection on files with wide headers or long first lines.

* `guess_line_ending` now scans the input in chunks up to a 64KB hard cap, returning as soon as one separator has a clear majority. Near-tie chunk-boundary artifacts no longer cause spurious warnings; only true ties at the hard cap fall back to `"\n"` and emit a `:no_clear_row_sep` warning at `:error` severity (silent miss-parse risk).

### New / Changed Options

* **`buffer_size` is now a public option** — peek buffer chunk size for non-seekable inputs (pipes, gzip readers, HTTP/S3 bodies). Default `16_384`. Out-of-range values warn and clamp to the supported range rather than raising.

* **`auto_row_sep_chars` default changed to `4096`** (was `500` in 1.16.x). Sized to cover wide-header CSVs in a single read. Bump it higher if your files have very wide headers or long comment preambles.

### Bug Fixes

* **Files ending in a lone `\r`** are now correctly detected as `\r`-terminated instead of falling through to a "no clear row separator" warning.

* **`remove_empty_values` now treats Unicode whitespace as empty** — a field containing only whitespace, including characters like non-breaking space (U+00A0) or ideographic space (U+3000), is now dropped, the same way Ruby's `String#blank?` behaves. Previously only ASCII whitespace counted (and only Rails apps got the Unicode behavior, via `blank?` — an inconsistency that's now gone). Behavior is identical with or without the C extension.

* **`remove_zero_values` now also removes signed zeros** — `+0`, `-0`, `-0.0`, `+0.00`, etc. are recognized as zero and dropped, just like `0` and `0.0`. (Only applies when `remove_zero_values: true`, which is off by default.)

### Performance

Measured against 1.16.4 (Apple M4, Ruby 3.4.7):

* **C-accelerated path (the default):** quote-heavy, large-field, and wide CSVs parse meaningfully faster — roughly **7–22% faster** (city/address-style files ~10–12%; long-field and wide files the most). CSVs with very short lines and many tiny fields are up to ~3% slower — a side effect of the larger default auto-detection scan window (see `auto_row_sep_chars`); set it back to a smaller value if that matters for your workload. Net: solid wins where there's real per-row work, a small cost on the trivially-cheap cases.
* **Ruby fallback path (`acceleration: false`):** faster on nearly every file — typically **3–20% faster** than 1.16.4, with the biggest gains on wide and many-small-field CSVs.

Per-file breakdown: [`docs/releases/1.17.0/performance_notes.md`](docs/releases/1.17.0/performance_notes.md).

## 1.16.6 (2026-05-21)

RSpec tests: **1,467 → 1,591** (+124 tests)

### Bug Fixes

  - fixed [Issue #334](https://github.com/tilo/smarter_csv/issues/334) with escaped double quote followed by comma. Thanks to [conorg](https://github.com/conorg)
  - fixed bug when using `headers: { except: }`
  - added more tests

## 1.16.5 (2026-05-17)

### Bug Fix

  - fixing issue with `remove_empty_hashes: false` not being honored in accelerated path (does not affect you when you use default settings)


## 1.16.4 (2026-04-21) — Bug Fixes

RSpec tests: **1,434 → 1,467** (+33 tests)

### Bug Fixes

* Fixed bug in `SmarterCSV.errors` that could lose collected records when processing raises mid-stream,
  e.g. when `bad_row_limit:` was exceeded (`TooManyBadRows`), or when a user's block raised through `.process` / `.each` / `.each_chunk`.

* Fixed `enforce_utf8_encoding` incorrectly replacing all non-ASCII bytes when the input string was tagged as `ASCII-8BIT` (binary).
  The encoding is now relabeled to UTF-8 before transcoding, so only genuinely invalid byte sequences are replaced.

## 1.16.3 (2026-04-14) — New Feature

RSpec tests: **1,425 → 1,434** (+9 tests)

### New Features

* **`write_headers: false`** — new `SmarterCSV::Writer` option to suppress the header line when appending rows to an existing CSV file opened in `'a'` mode.
  Defaults to `true` (existing behavior, fully backwards-compatible).
  
  See [Appending to an Existing CSV File](docs/basic_write_api.md#appending-to-an-existing-csv-file).

### Other
* Refactor of internal options handling

## 1.16.2 (2026-03-30) — Bug Fixes

RSpec tests: **1,410 → 1,425** (+15 tests)

### Bug Fixes

* Fixed `value_converters` to accept lambdas and Procs in addition to class-based converters.
  Thanks to [Jonas Staškevičius](https://github.com/pirminis) for issue [#329](https://github.com/tilo/smarter_csv/issues/329).

* Fixed blank header auto-naming to use **absolute column position**, consistent with extra data column naming.
  `name,,` now produces `column_2`/`column_3` instead of `column_1`/`column_2`.
  ⚠️ If your code references auto-generated keys for blank headers, update those to use the absolute column position.

* Fixed `Writer`: when both `map_headers:` and `header_converter:` were used together, `map_headers` was silently ignored.
  `map_headers` is now applied first, then `header_converter` on top.

## 1.16.1 (2026-03-16) — Bug Fixes & New Features

RSpec tests: **1,247 → 1,410** (+163 tests)

### New Features

* **`SmarterCSV.errors`** — class-level error access after any `process`, `parse`, `each`, or `each_chunk` call.
  Exposes the same `reader.errors` hash without requiring access to the `Reader` instance.
  Errors are cleared at the start of each call and stored per-thread (safe in Puma/Sidekiq).

  ```ruby
  # Previously — required Reader instance to access errors
  reader = SmarterCSV::Reader.new('data.csv', on_bad_row: :skip)
  reader.process
  puts reader.errors[:bad_row_count]

  # Now — works with the class-level API too
  SmarterCSV.process('data.csv', on_bad_row: :skip)
  puts SmarterCSV.errors[:bad_row_count]
  ```

> **Note:** `SmarterCSV.errors` only surfaces errors from the **most recent run on the
> current thread**. In a multi-threaded environment (Puma, Sidekiq), each thread maintains
> its own error state independently. If you call `SmarterCSV.process` twice in the same
> thread, the second call's errors replace the first's. For long-running or complex
> pipelines where you need to aggregate errors across multiple files, use the Reader API.
>
> ⚠️ **Fibers:** `SmarterCSV.errors` uses `Thread.current` for storage, which is **shared
> across all fibers running in the same thread**. If you process CSV files concurrently
> in fibers (e.g. with `Async`, `Falcon`, or manual `Fiber` scheduling), `SmarterCSV.errors`
> may return stale or wrong results. **Use `SmarterCSV::Reader` directly** — errors are
> scoped to the reader instance and are always correct regardless of fiber context.

### Bug Fixes

* fixed [#325](https://github.com/tilo/smarter_csv/issues/325): `col_sep` in quoted headers was handled incorrectly; Thanks to Paho Lurie-Gregg.
* fixed issue with quoted numeric fields that were not converted to numeric

### Tests

* Added 163 tests covering new features and corner cases

## 1.16.0 (2026-03-12) — improved RFC 4180 quote handling, new APIs, large performance gains

[Full details](docs/releases/1.16.0/changes.md) · [Benchmarks](docs/releases/1.16.0/benchmarks.md) · [Performance notes](docs/releases/1.16.0/performance_notes.md)

RSpec tests: **714 → 1,247** (+533 tests)

### (Bug Fix) `quote_boundary:` — new default for how mid-field quotes are handled

**In short — most users will see incorrect output silently improve. If your CSV files don't contain stray `"` characters in the middle of unquoted fields, you are not affected. If they do, the new default produces correct output where the old default produced corrupted output.**

A new option `quote_boundary:` controls when a `"` character marks the start or end of a quoted field versus when it's a literal character inside the field.

* `quote_boundary: :standard` (the new default) — quotes are only recognized as field delimiters at field boundaries (start of a field, or immediately before `col_sep` / end of line). A `"` that appears in the middle of an unquoted field is treated as a literal character. This matches RFC 4180 and Ruby's standard `CSV` library.
* `quote_boundary: :legacy` — **not recommended.** Restores the pre-1.16.0 behavior, where any `"` could open a quoted region. This is the behavior that produced silently corrupt output on files with stray mid-field quotes; it exists only as an escape hatch for code that built workarounds on top of the buggy output. New code should never use this.

In practice, the old `:legacy` behavior was silently producing corrupt output whenever a CSV file contained a stray mid-field `"` — so for most users this change makes output **correct** where it was wrong before, not the other way around.

#### You are NOT affected if:
  - Your CSV files don't contain any `"` characters mid-field (the common case).
  - Your CSV files quote fields cleanly per RFC 4180 (well-formed `"..."` around each quoted field, no stray quotes inside other fields).

#### You are affected if:
  - Your CSV files contain stray `"` characters in the middle of unquoted fields (e.g. `5'6"`, `Joe "the Hat" Smith` without surrounding quotes), **and** you had downstream code that compensated for the previously-corrupted parse output.

#### How to migrate

For almost everyone: do nothing. Upgrade and observe that the output is the same or more correct.

The `quote_boundary: :legacy` option exists only as a short-term escape hatch — **we do not advise using it**, because it re-enables the buggy parse behavior that motivated this change. If your code built workarounds on top of the previously-corrupted output, the right fix is to remove those workarounds and rely on the new `:standard` behavior, not to opt back into the bug:

```ruby
# Only as a temporary escape hatch — not recommended for new code:
SmarterCSV.process('file.csv', quote_boundary: :legacy)
```

See [Parsing Strategy](docs/parsing_strategy.md) for details on how each mode handles edge cases.

### Performance

 * **1.8×–8.6× faster** than Ruby `CSV.read` (raw tokenization only; no post-processing)
 * **7×–129× faster** than Ruby `CSV.table` (nearest equivalent output)
 * **up to 2.4× faster** for accelerated path vs 1.15.2 (15/19 benchmark files faster)
 * **up to 2× faster** for Ruby path vs 1.15.2
 * **9×–65× faster** for accelerated path vs 1.14.4

Measured on 19 benchmark files, Apple M1, Ruby 3.4.7. See [benchmarks](docs/releases/1.16.0/benchmarks.md).

### New Read API

 * **`SmarterCSV.parse(csv_string, options)`**: can now parse a CSV string directly. See [Migrating from Ruby CSV](docs/migrating_from_csv.md).
 * **`SmarterCSV.each` / `Reader#each`**: row-by-row enumerator; `Reader` now includes `Enumerable`.
 * **`SmarterCSV.each_chunk` / `Reader#each_chunk`**: chunked enumerator yielding `(Array<Hash>, chunk_index)`.

### New Options

 * **`on_bad_row:`** — bad row quarantine: `:skip`, `:collect`, `:raise`, or callable. See [Bad Row Quarantine](docs/bad_row_quarantine.md).
 * **`bad_row_limit: N`** — raises `SmarterCSV::TooManyBadRows` after N bad rows.
 * **`collect_raw_lines:`** (default: `true`) — include raw line in bad-row error records.
 * **`field_size_limit: N`** — cap field size in bytes; prevents DoS from unclosed quotes. Raises `SmarterCSV::FieldSizeLimitExceeded`.
 * **`headers: { only: [...] }` / `headers: { except: [...] }`** — column selection; excluded columns skipped in C hot path. See [Column Selection](docs/column_selection.md).
 * **`nil_values_matching:`** — replaces deprecated `remove_values_matching:`.
 * **`missing_headers:`** (default: `:auto`) — replaces deprecated `strict:`.
 * **`verbose: :quiet/:normal/:debug`** — replaces deprecated `verbose: true/false`.
 * **`on_start:` / `on_chunk:` / `on_complete:`** — instrumentation hooks. See [Instrumentation](docs/instrumentation.md).

### New Write API

 * **IO/StringIO support**: `SmarterCSV.generate` and `Writer.new` now accept any `IO`-compatible object. See [Write API](docs/basic_write_api.md).
 * **`SmarterCSV.generate` returns a String** when called without a destination argument.
 * **Streaming mode**: when `headers:` or `map_headers:` is provided upfront, Writer skips the temp file and streams directly.
 * **`encoding:` / `write_nil_value:` / `write_empty_value:` / `write_bom:`** — new writer options.

### Deprecations

 * `remove_values_matching:` → use `nil_values_matching:`
 * `strict:` → use `missing_headers: :raise/:auto`
 * `verbose: true/false` → use `verbose: :debug/:normal`

### Bug Fixes

 * **Empty headers** ([#324](https://github.com/tilo/smarter_csv/issues/324), [#312](https://github.com/tilo/smarter_csv/issues/312)): empty/whitespace-only header fields now auto-generate names via `missing_header_prefix`.
 * **All library output now goes to `$stderr`** — nothing written to `$stdout`.
 * **`SmarterCSV.generate` raises `ArgumentError`** (not blank `RuntimeError`) when called without a block.
 * **Writer temp file** no longer hardcoded to `/tmp` (fixes Windows); properly cleaned up with `Tempfile#close!`.
 * **Writer `StringIO`**: `finalize` no longer attempts to close a caller-owned `StringIO`.

## 1.15.3 (2026-05-17)

### Bug Fix

  - fixing issue with `remove_empty_hashes: false` not being honored in accelerated path (does not affect you when you use default settings)

## 1.15.2 (2026-02-20)

### Performance Optimizations
 - 1.6× to 7.2× faster than CSV.read
 - 6× to 113× faster than Ruby’s CSV.table
 - 5.4× to 37.4× faster than SmarterCSV 1.14.4 (with C-acceleration)
 - 1.4× to 9.5× faster than SmarterCSV 1.14.4 (without C-acceleration, pure Ruby path)

 [More details here](https://tilo-sloboda.medium.com/smartercsv-1-15-2-faster-than-raw-csv-arrays-benchmarks-zsv-and-the-full-pipeline-2c12a798032e) and [here](https://github.com/tilo/smarter_csv/pull/319)

## 1.15.1 (2026-02-17)

### Bug Fix

 * **Fix for quoted fields ending with backslash** ([issue #316](https://github.com/tilo/smarter_csv/issues/316), [issue #252](https://github.com/tilo/smarter_csv/issues/252)): Since v1.8.5, SmarterCSV unconditionally treated `\"` as an escaped quote, which caused `MalformedCSV` or `EOFError` for CSV files containing literal backslashes in quoted fields (e.g. Windows paths like `"C:\Users\"`).

### New Option

 * **New option `quote_escaping`**: Controls how quotes are escaped inside quoted fields. Default: `:auto`. See [Parsing Strategy](docs/parsing_strategy.md) for details.
   - `:auto` (default): Tries backslash-escape interpretation first, falls back to RFC 4180 if parsing fails. This handles both conventions automatically without breaking existing data.
   - `:double_quotes` (RFC 4180): Only doubled quotes (`""`) escape a quote character. Backslash is always literal.
   - `:backslash` (MySQL/Unix): `\"` is treated as an escaped quote.

## 1.15.0 (2026-02-04)

* Dropping support for Ruby 2.5

* Performance Optimizations
  - 39% less memory allocated
  - 43% fewer objects created
  - ~5× faster at P90 vs SmarterCSV 1.14.4
  - ~3–7× faster at P90 vs Ruby CSV

### New Features

 * **Chunk index in block processing**: When using block-based processing, an optional second parameter `chunk_index` is now passed to the block. This 0-based index is useful for progress tracking and debugging. The change is backwards compatible - existing code continues to work.

   ```ruby
   SmarterCSV.process(file, chunk_size: 100) do |chunk, chunk_index|
     puts "Processing chunk #{chunk_index}..."
     Model.import(chunk)
   end
   ```

### Exception Improvements

 * `MissingKeys#keys` - programmatic access to missing keys without parsing error messages ([PR #314](https://github.com/tilo/smarter_csv/pull/314), thanks to Skye Shaw)
 * `DuplicateHeaders#headers` - programmatic access to duplicate headers without parsing error messages

   ```ruby
   # Example: accessing missing keys programmatically
   rescue SmarterCSV::MissingKeys => e
     e.keys  # => [:employee_id, :department]
   end

   # Example: accessing duplicate headers programmatically
   rescue SmarterCSV::DuplicateHeaders => e
     e.headers  # => [:email]
   end
   ```

### Performance Improvements

 * **New `parse_line_to_hash_c` function**: Builds Ruby hash directly during parsing, eliminating intermediate array allocations. Previously, parsing created a values array, then `zip()` created pairs array, then `to_h()` built the hash. Now done in a single pass.

 * **Shared empty string optimization**: Reuses a single frozen empty string for all empty CSV fields, reducing object allocations and GC pressure.

 * **Faster quote counting**: New `count_quote_chars_c` function replaces Ruby's `each_char` iteration, eliminating one String object allocation per character.

 * **Conditional nil padding**: Missing columns only padded with `nil` when `remove_empty_values: false`, avoiding unnecessary work in the default case.

### Ruby Code Optimizations

 * **Frozen regex constants**: Numeric conversion patterns (`FLOAT_REGEX`, `INTEGER_REGEX`, `ZERO_REGEX`) are now pre-compiled and frozen, eliminating millions of regex compilations for large files. This alone reduced numeric conversion overhead from +75% to +4%.

 * **In-place hash modification**: Hash transformations now modify hashes in-place instead of creating copies, reducing memory allocations by 39% and object count by 43%.

### Benchmark Results

Benchmarks using Ruby 3.4.7 on M1 Apple Silicon. All times in seconds.

**Summary:**

| Comparison           | Range               | Comments             |    P90 |
|----------------------|---------------------|----------------------|--------|
| vs SmarterCSV 1.14.4 | 2.6x -  3.5x faster | up to 20.5x for some |    ~5x |
| vs CSV hashes        | 1.9x -  3.8x faster | up to  6.7x for some |    ~3x |
| vs CSV.table         | 4.3x - 10.1x faster | up to 12.0x for some | ~7..8x |

_P90 measured over the full set of benchmarked files_

**These gains come while returning fully usable hashes with conversions, not raw arrays that require post-processing.**

**Memory improvements:** 39% less memory allocated, 43% fewer objects created


**vs SmarterCSV 1.14.4:**

| File                      | Size   | Rows | 1.14.4 | 1.15.0 | Speedup    |
|---------------------------|--------|------|--------|--------|------------|
| worldcities.csv           |   5 MB |  48K |  1.27s |  0.49s |  **2.6x**  |
| LANDSAT_ETM_C2_L1_50k.csv |  31 MB |  50K |  6.73s |  1.99s |  **3.4x**  |
| PEOPLE_IMPORT.csv         |  62 MB |  50K |  8.43s |  2.43s |  **3.5x**  |
| wide_500_cols_20k.csv     |  98 MB |  20K | 19.38s |  5.09s |  **3.8x**  |
| long_fields_20k.csv       |  22 MB |  20K |  3.05s |  0.15s | **20.5x**  |
| embedded_newlines_20k.csv | 1.5 MB |  20K |  0.59s |  0.12s |  **5.1x**  |

**vs Ruby CSV 3.3.5:**

For an apples-to-apples comparison, we must compare parsers that return the same result structure and perform comparable work.
SmarterCSV returns an array of hashes with symbol keys and type conversion applied, so raw CSV array parsing is not a fair comparison.

**Beware of comparisons that focus solely on raw CSV parsing.**
Such benchmarks measure only tokenization, while real-world usage still **requires substantial post-processing to produce usable data**. Leaving this work out -- hash construction, normalization, type conversion, and edge-case handling to produce usable data -- consistently **understates the actual cost of CSV ingestion**.

For this reason, **CSV.table is the closest equivalent to SmarterCSV.**

| File                      | Size   | Rows | CSV hashes | CSV.table | 1.15.0 | vs hashes | vs table   |
|---------------------------|--------|------|------------|-----------|--------|-----------|------------|
| worldcities.csv           |   5 MB |  48K |    1.06s   |   2.12s   |  0.49s | **2.2x**  |  **4.3x**  |
| LANDSAT_ETM_C2_L1_50k.csv |  31 MB |  50K |    3.85s   |   9.25s   |  1.99s | **1.9x**  |  **4.7x**  |
| PEOPLE_IMPORT.csv         |  62 MB |  50K |    9.10s   |  24.39s   |  2.43s | **3.8x**  | **10.1x**  |
| wide_500_cols_20k.csv     |  98 MB |  20K |   34.24s   |  61.24s   |  5.09s | **6.7x**  | **12.0x**  |
| long_fields_20k.csv       |  22 MB |  20K |    0.34s   |   0.81s   |  0.15s | **2.3x**  |  **5.5x**  |
| whitespace_heavy_20k.csv  | 3.3 MB |  20K |    0.30s   |   0.83s   |  0.12s | **2.5x**  |  **7.0x**  |

_CSV hashes = `CSV.read(file, headers: true).map(&:to_h)` (string keys, no conversion, still requires post-processing)_
_CSV.table = `CSV.table(file).map(&:to_h)` (symbol keys + numeric conversion, still requires post-processing)_
_worldcities.csv is [from here](https://simplemaps.com/data/world-cities)_


### Misc Fixes

 * Fix compilation error on ARM macOS (`-march=native` unsupported) ([PR #313](https://github.com/tilo/smarter_csv/pull/313), thanks to Skye Shaw)
 * CI improvements: Ruby 3.4 support, Codecov action update ([PR #311](https://github.com/tilo/smarter_csv/pull/311), thanks to Mark Bumiller)

## 1.14.4 (2025-05-26)
 * Bugfix: SmarterCSV::Reader fixing issue with header containing spaces ([PR 305](https://github.com/tilo/smarter_csv/pull/305) thanks to Felipe Cabezudo)

## 1.14.3 (2025-05-04)
 * Improved C-extension parsing logic:
   - Added fast path for unquoted fields to avoid unnecessary quote checks.
   - Aded inline whitespace stripping inside the C parser
 * Performance
   -  Significantly reduced per-line overhead in non-quoted, wide CSVs (e.g. fixed-width data exports).
   - Benchmarks show ~10–40% speedup over v1.14.2 depending on structure and quoting.

## 1.14.2 (2025-04-10)
 * bugfix: SmarterCSV::Writer fixing corner case with `quote_headers: true` ([issue 301](https://github.com/tilo/smarter_csv/issues/301))
 * new option: `header_converter` allows to programatically modify the headers

## 1.14.1 (2025-04-09)
 * bugfix: SmarterCSV::Writer empty hash results in a blank line ([issue 299](https://github.com/tilo/smarter_csv/issues/299))
 * bugfix: SmarterCSV::Writer need to automatically quote problematic headers ([issue #300](https://github.com/tilo/smarter_csv/issues/300))
 * new option: `quote_headers` allows to explicitly quote all headers

## 1.14.0 (2025-04-07)
 * adding advanced configuration options for writing CSV files. ([issue 297](https://github.com/tilo/smarter_csv/issues/297) thanks to Robert Reiz, [issue 296](https://github.com/tilo/smarter_csv/issues/296))

## 1.13.1 (2024-12-12)
  * fix bug with SmarterCSV.generate with `force_quotes: true` ([issue 294](https://github.com/tilo/smarter_csv/issues/294))

## 1.13.0 (2024-11-06) — Three default-behavior changes that prevent silent data loss

This release flipped three defaults so that SmarterCSV no longer silently loses data in three specific edge cases. For most users this is a quiet improvement — files that used to lose rows or columns silently now parse correctly with no code changes. Each change below has a short "affected if / not affected if" so you can skip past it quickly.

The motivation for all three changes is the same: data loss should never be silent. Either parse it correctly, or raise loudly.

### Change 1 (Bug Fix): extra columns in a row are auto-named instead of dropped

(Thanks to James Fenley, [issue #284](https://github.com/tilo/smarter_csv/issues/284).)

If a CSV row had more columns than the header (e.g. header has 6 columns, a row has 8), the extras used to be **silently dropped**. As of 1.13.0 they survive as `:column_7`, `:column_8`, etc.

#### You are NOT affected if:
  - Your CSV files have exactly as many columns per row as headers (the common case).

#### You are affected if:
  - Your CSV files have rows with extra columns past the header **and** your code expects only the header-listed keys.

#### How to migrate

If you want the old "ignore extras" behavior, drop the extra keys yourself. If you want loud failure instead, use the strict mode:

```ruby
# Raise SmarterCSV::MalformedCSV on extra columns:
SmarterCSV.process('file.csv', strict: true)
```

(In 1.16.0 this option was renamed to `missing_headers: :raise`, but `strict: true` still works.)

### Change 2 (Bug Fix): unbalanced quotes raise `MalformedCSV` instead of producing garbage

(Thanks to Simon Rentzke, James Fenley, Randall B, and Matthew Kennedy. Issues [#283](https://github.com/tilo/smarter_csv/issues/283), [#288](https://github.com/tilo/smarter_csv/issues/288).)

Files with an unbalanced `quote_char` (an opening `"` with no matching close) used to parse to corrupted output. As of 1.13.0 they raise `SmarterCSV::MalformedCSV`.

#### You are NOT affected if:
  - Your CSV files have well-formed quotes (the common case).

#### You are affected if:
  - Some of your input files have unbalanced quotes and you used to silently live with the garbled output.

#### How to migrate

If you need to keep processing other files even when one is malformed, rescue the new exception:

```ruby
begin
  SmarterCSV.process('file.csv')
rescue SmarterCSV::MalformedCSV => e
  warn "Skipping malformed file: #{e.message}"
end
```

### Change 3 (Bug Fix): `user_provided_headers:` now implies `headers_in_file: false`

([Issue #282](https://github.com/tilo/smarter_csv/issues/282).)

This one fixes a quiet footgun: if you passed `user_provided_headers:` and the file had **no** header row, SmarterCSV used to treat the first data row as a header and silently drop it. As of 1.13.0, setting `user_provided_headers:` automatically sets `headers_in_file: false`, so the first row is treated as data — which is what you almost always wanted.

#### You are NOT affected if:
  - You don't use `user_provided_headers:`.
  - You use `user_provided_headers:` with files that have no header line (the common case — that's what the option is for).

#### You are affected if:
  - You pass `user_provided_headers:` **and** your CSV file **does** have a header line that needs to be skipped.

#### How to migrate

If your file has a header line **and** you're overriding it with `user_provided_headers:`, add `headers_in_file: true` explicitly so the existing header line is skipped:

```ruby
# File has a header row that you want to override:
SmarterCSV.process(
  'file.csv',
  user_provided_headers: [:id, :name, :email],
  headers_in_file: true,    # skip the header row in the file
)
```

Without `headers_in_file: true`, you will get an extra hash at the top of your results containing the file's original header strings as values — that's the symptom to look for.

### Documentation

* Improved documentation for handling numeric columns with leading zeroes (e.g. ZIP codes). Use `convert_values_to_numeric: { except: [:zip] }` to keep that column as a string. (Available since 1.10.x.) Thanks to David Moles, [issue #151](https://github.com/tilo/smarter_csv/issues/151).

## 1.12.1 (2024-07-10)
  * Improved column separator detection by ignoring quoted sections [#276](https://github.com/tilo/smarter_csv/pull/276) (thanks to Nicolas Castellanos)

## 1.12.0 (2024-07-09)
  * Added Thread-Safety: added SmarterCSV::Reader to process CSV files in a thread-safe manner ([issue #277](https://github.com/tilo/smarter_csv/pull/277))
  * SmarterCSV::Writer changed default row separator to the system's row separator (`\n` on Linux, `\r\n` on Windows)
  * added a doc tree
  
  * POTENTIAL ISSUE:
    
    Version 1.12.x has a change of the underlying implementation of `SmarterCSV.process(file_or_input, options, &block)`. 
    Underneath it now uses this interface:
      ```
        reader = SmarterCSV::Reader.new(file_or_input, options)

        # either simple one-liner:
        data = reader.process

        # or block format:
        data = reader.process do 
           # do something here
        end
      ```
    It still supports calling `SmarterCSV.process` for backwards-compatibility, but it no longer provides access to the internal state, e.g. raw_headers.

      `SmarterCSV.raw_headers` -> `reader.raw_headers`
      `SmarterCSV.headers` -> `reader.headers`

    If you need these features, please update your code to create an instance of `SmarterCSV::Reader` as shown above.


## 1.11.2 (2024-07-06)
  * fixing missing errors definition
    
## 1.11.1 (2024-07-05) (YANKED)
  * improved behavior of Writer class
  * added SmarterCSV.generate shortcut for CSV writing
    
## 1.11.0 (2024-07-02)
  * added SmarterCSV::Writer to output CSV files ([issue #44](https://github.com/tilo/smarter_csv/issues/44))
  
## 1.10.3 (2024-03-10)
  * fixed issue when frozen options are handed in (thanks to Daniel Pepper)
  * cleaned-up rspec tests (thanks to Daniel Pepper)
  * fixed link in README (issue #251)

## 1.10.2 (2024-02-11)
  * improve error message for missing keys

## 1.10.1 (2024-01-07)
  * fix incorrect warning about UTF-8 (issue #268, thanks hirowatari)

## 1.10.0 (2023-12-31) — Behavior changes for `user_provided_headers:` and duplicate headers

Two small behavior changes plus performance and memory improvements. Most users are not affected. Read on for who needs to look closer.

### Change 1 (Improvement): `user_provided_headers:` is now taken literally (no transformations, no duplicates)

**In short — if you use `user_provided_headers:`, write the list in the exact form you want the result keys (all symbols *or* all strings), and make sure there are no duplicates. For most users this is already what you were doing.**

Before 1.10.0, any list you passed as `user_provided_headers:` was run through the same header pipeline as in-file headers — `strings_as_keys` could flip strings to symbols, etc. Duplicates were silently accepted. As of 1.10.0, the list is used **literally**: no transformations are applied, and duplicates raise `SmarterCSV::DuplicateHeaders`.

This is almost always what people actually wanted: if you're explicitly listing the headers, you want *those* headers, not a transformed version of them.

#### You are NOT affected if:
  - You don't use `user_provided_headers:`.
  - Your `user_provided_headers:` list is already in the form you want (all symbols *or* all strings, no duplicates).
  In these cases, you can just upgrade without any code changes.

#### You are affected if either is true:
  - You pass `user_provided_headers:` **and** relied on `strings_as_keys:` to flip between string/symbol keys.
  - You pass `user_provided_headers:` **and** had accidental duplicates in the list that the library used to silently accept (this case would be very odd).

#### How to migrate

```ruby
# If you want symbol keys, write symbols directly:
SmarterCSV.process('file.csv', user_provided_headers: [:id, :name, :email])

# If you want string keys, write strings directly:
SmarterCSV.process('file.csv', user_provided_headers: ['id', 'name', 'email'])
```

Drop any `strings_as_keys:` option you used alongside `user_provided_headers:` — it's ignored in that case now.

If you see `SmarterCSV::DuplicateHeaders` after upgrading, your list has a repeat in it — fix the duplicate and you're done.

### Change 2 (Improvement): duplicate headers in the CSV file are now auto-disambiguated

**In short — if your input CSV has duplicate column headers, they now Just Work instead of colliding. If your files don't have duplicate headers, you are not affected.**

`duplicate_header_suffix:` used to default to `nil`. Now it defaults to `''` (empty string), which means a file with headers like `name,name,name` becomes keys `name`, `name2`, `name3` automatically — no more silently overwriting earlier columns.

#### You are affected if:
  - You depended on SmarterCSV raising or failing fast when a CSV has duplicate headers (e.g. as a data-quality check at the boundary of your pipeline).

#### You are NOT affected if:
  - Your CSVs don't have duplicate headers.
  - You already explicitly set `duplicate_header_suffix:` in your code.

#### How to migrate

If you want the old strict behavior, set the option explicitly to `nil`:

```ruby
SmarterCSV.process('file.csv', duplicate_header_suffix: nil)
```

### Other

* Performance and memory improvements
* Internal code refactor

## 1.9.3 (2023-12-16)
  * raise SmarterCSV::IncorrectOption when `user_provided_headers` are empty
  * code refactor / no functional changes
  * added test cases

## 1.9.2 (2023-11-12)
  * fixed bug with '\\' at end of line (issue #252, thanks to averycrespi-moz)
  * fixed require statements (issue #249, thanks to PikachuEXE, courtsimas)
    
## 1.9.1 (2023-10-30) (YANKED)
  * yanked
  * no functional changes
  * refactored directory structure
  * re-added JRuby and TruffleRuby to CI tests
  * no C-accelleration for JRuby
  * refactored options parsing
  * code coverage / rubocop

## 1.9.0 (2023-09-04)
  * fixed issue #139

  * Error `SmarterCSV::MissingHeaders` was renamed to `SmarterCSV::MissingKeys`
    
  * CHANGED BEHAVIOR:
    When `key_mapping` option is used. (issue #139)
    Previous versions just printed an error message when a CSV header was missing during key mapping.
    Versions >= 1.9 will throw `SmarterCSV::MissingHeaders` listing all headers that were missing during mapping.

  * Notable details for `key_mapping` and `required_headers`:

    * `key_mapping` is applied to the headers early on during `SmarterCSV.process`, and raises an error if a header in the input CSV file is missing, and we can not map that header to its desired name.

    Mapping errors can be surpressed by using:
    * `silence_missing_keys` set to `true`, which silence all such errors, making all headers for mapping optional.
    * `silence_missing_keys` given an Array with the specific header keys that are optional
    The use case is that some header fields are optional, but we still want them renamed if they are present.

    * `required_headers` checks which headers are present **after** `key_mapping` was applied.

## 1.8.5 (2023-06-25)
  * fix parsing of escaped quote characters (thanks to JP Camara)
    
## 1.8.4 (2023-04-01)
  * fix gem loading issue (issue #232, #234)
  
## 1.8.3 (2023-03-30)
  * bugfix: windows one-column files were raising NoColSepDetected (issue #229)
    

## 1.8.2 (2023-03-21)
  * bugfix: do not raise `NoColSepDetected` for CSV files with only one column in most cases (issue #222)
            If the first lines contain non-ASCII characters, and no col_sep is detected, it will still raise `NoColSepDetected`

## 1.8.1 (2023-03-19)
  * added validation against invalid values for :col_sep, :row_sep, :quote_char (issue #216)
  * deprecating `required_headers` and replace with `required_keys` (issue #140)
  * fixed issue with require statement

## 1.8.0 (2023-03-18) BREAKING
  * NEW DEFAULTS: `col_sep: :auto`, `row_sep: :auto`. Fully automatic detection by default.
    
    MAKE SURE to rescue `NoColSepDetected` if your CSV files can have unexpected formats, 
              e.g. from users uploading them to a service, and handle those cases.

  * ignore Byte Order Marker (BOM) in first line in file (issues #27, #219)

## 1.7.4 (2023-01-13)
  * improved guessing of the column separator, thanks to Alessandro Fazzi

## 1.7.3 (2022-12-05)
  * new option :silence_missing_keys; if set to true, it ignores missing keys in `key_mapping`

## 1.7.2 (2022-08-29)
  * new option :with_line_numbers; if set to true, it adds :csv_line_number to each data hash (issue #130)
  
## 1.7.1 (2022-07-31)
  * bugfix for issue #195 #197 #200 which only appeared when called from Rails (thanks to Viacheslav Markin, Nicolas Rodriguez)

## 1.7.0 (2022-06-26) (replaced by 1.7.1)
  * added native code to accellerate line parsing by >10x over 1.6.0
  * added option `acceleration`, defaulting to `true`, to enable native code.
    Disable this option to use the ruby code for line parsing.
  * increased test coverage to 100%
  * rubocop changes

## 1.7.0.pre5 (2022-06-20)
  * fixed compiling
  * rubocop changes
  * published pre-release 

## 1.7.0.pre1 (2022-05-23)
  * added native code to accellerate line parsing by >10x over 1.6.0
  * added option `acceleration`, defaulting to `true`, to enable native code.
    Disable this option to use the ruby code for line parsing.
  * increased test coverage to 100%

## 1.6.1 (2022-05-06)
  * unused keys in `key_mapping` now generate a warning, no longer raise an exception
    This is preferable when `key_mapping` is done defensively for variabilities in the CSV files.

## 1.6.0 (2022-05-03)
  * completely rewrote line parser
  * added methods `SmarterCSV.raw_headers` and `SmarterCSV.headers` to allow easy examination of how the headers are processed.

## 1.5.2 (2022-04-29)
  * added missing keys to the SmarterCSV::KeyMappingError exception message #189 (thanks to John Dell)
  
## 1.5.1 (2022-04-27)
  * added raising of `KeyMappingError` if `key_mapping` refers to a non-existent key
  * added option `duplicate_header_suffix` (thanks to Skye Shaw)
    When given a non-nil string, it uses the suffix to append numbering 2..n to duplicate headers.
    If your code will need to process arbitrary CSV files, please set `duplicate_header_suffix`.

## 1.5.0 (2022-04-25)
  * fixed bug with trailing col_sep characters, introduced in 1.4.0
  * Fix deprecation warning in Ruby 3.0.3 / $INPUT_RECORD_SEPARATOR (thanks to Joel Fouse )

  * changed default for `comment_regexp` to be `nil` for a safer default behavior (thanks to David Lazar)
  **Note**
    This no longer assumes that lines starting with `#` are comments.
    If you want to treat lines starting with '#' as comments, use `comment_regexp: /\A#/`

## 1.4.2 (2022-02-12)
  * fixed issue with simplecov

## 1.4.1 (2022-02-12) (PULLED)
  * minor fix: also support `col_sep: :auto`
  * added simplecov

## 1.4.0 (2022-02-11)
  * dropped GPL license, smarter_csv is now only using the MIT License
  * added experimental option `col_sep: 'auto` to auto-detect the column separator (issue #183)
    The default behavior is still to assume `,` is the column separator. 
  * fixed buggy behavior when using `remove_empty_values: false` (issue #168)
  * fixed Ruby 3.0 deprecation

## 1.3.0 (2022-02-06)

### (Bug Fix) Small change for users of the `key_mapping:` option (issue #181)

**In short — if you use `key_mapping:`, this is a one-character fix per mapping. If you don't use `key_mapping:`, you are not affected.**

Previously, the values in a `key_mapping:` hash were silently coerced to symbols, so `'new_name'` and `:new_name` produced the same result key. As of 1.3.0, the values are used as-is — strings stay strings, symbols stay symbols. This gives you direct control over whether the result hashes use string or symbol keys.

#### You are NOT affected if any of these are true:
  - You don't use `key_mapping:`.
  - Your `key_mapping:` already uses symbol values (e.g. `:new_name`).
  - Your downstream code already reads result hashes with string keys.
  In these cases, you can just upgrade without any code changes.

#### You are affected if all three are true:
  - You pass `key_mapping:` to `SmarterCSV.process` (or `process_csv` in older code), **and**
  - The values in that hash are strings (e.g. `'new_name'`, not `:new_name`), **and**
  - Your downstream code reads the result hashes with symbol keys (e.g. `row[:new_name]`).
  This needs a small code-change

#### How to migrate

Pick whichever is the smaller diff in your code:

```ruby
# Option A — keep symbol keys in the result (one extra colon per line):
SmarterCSV.process('file.csv', key_mapping: { 'Old Header' => :new_name })
#                                                             ^ add the colon

# Option B — switch your reads to string keys:
row['new_name']   # instead of row[:new_name]
```

That's the whole migration. Everything else in 1.3.0 is source-compatible with 1.2.x.

## 1.2.9 (2021-11-22) (PULLED)
 * fix bug for key_mappings (issue #181)
   The values of the `key_mappings` hash will now be used "as is", and no longer forced to be symbols

## 1.2.8 (2020-02-04)
 * fix deprecation warnings on Ruby 2.7 (thank to Diego Salido)

## 1.2.7 (2020-02-03)

## 1.2.6 (2018-11-13)
 * fixing error caused by calling f.close when we do not hand in a file

## 1.2.5 (2018-09-16)
 * fixing issue #136 with comments in CSV files
 * fixing error class hierarchy

## 1.2.4 (2018-08-06)
 * using Rails blank? if it's available

## 1.2.3 (2018-01-27)
 * fixed regression / test
 * fuxed quote_char interpolation for headers, but not data (thanks to Colin Petruno)
 * bugfix (thanks to Joshua Smith for reporting)

## 1.2.0 (2018-01-20)
 * add default validation that a header can only appear once; raises `SmarterCSV::DuplicateHeaders` when it doesn't
 * add option `required_headers`

## 1.1.5 (2017-11-05)
 * fix issue with invalid byte sequences in header (issue #103, thanks to Dave Myron)
 * fix issue with invalid byte sequences in multi-line data (thanks to Ivan Ushakov)
 * analyze only 500 characters by default when `:row_sep => :auto` is used.
   added option `row_sep_auto_chars` to change the default if necessary. (thanks to Matthieu Paret)

## 1.1.4 (2017-01-16)
 * fixing UTF-8 related bug which was introduced in 1.1.2 (thanks to Tirdad C.)

## 1.1.3 (2016-12-30)
 * added warning when options indicate UTF-8 processing, but input filehandle is not opened with r:UTF-8 option

## 1.1.2 (2016-12-29)
 * added option `invalid_byte_sequence` (thanks to polycarpou)
 * added comments on handling of UTF-8 encoding when opening from File vs. OpenURI (thanks to KevinColemanInc)

## 1.1.1 (2016-11-26)
 * added option to `skip_lines` (thanks to wal)
 * added option to `force_utf8` encoding (thanks to jordangraft)
 * bugfix if no headers in input data (thanks to esBeee)
 * ensure input file is closed (thanks to waldyr)
 * improved verbose output (thankd to benmaher)
 * improved documentation

## 1.1.0 (2015-07-26)
 * added feature :value_converters, which allows parsing of dates, money, and other things (thanks to Raphaël Bleuse, Lucas Camargo de Almeida, Alejandro)
 * added error if :headers_in_file is set to false, and no :user_provided_headers are given (thanks to innhyu)
 * added support to convert dashes to underscore characters in headers (thanks to César Camacho)
 * fixing automatic detection of \r\n line-endings (thanks to feens)

## 1.0.19 (2014-10-29)
 * added option :keep_original_headers to keep CSV-headers as-is (thanks to Benjamin Thouret)

## 1.0.18 (2014-10-27)
 * added support for multi-line fields / csv fields containing CR (thanks to Chris Hilton) (issue #31)

## 1.0.17 (2014-01-13)
 * added option to set :row_sep to :auto , for automatic detection of the row-separator (issue #22)

## 1.0.16 (2014-01-13)
 * :convert_values_to_numeric option can now be qualified with :except or :only (thanks to Hugo Lepetit)
 * removed deprecated `process_csv` method

## 1.0.15 (2013-12-07)
 * new option:
   * :remove_unmapped_keys  to completely ignore columns which were not mapped with :key_mapping (thanks to Dave Sanders)

## 1.0.14 (2013-11-01)
 * added GPL-2 and MIT license to GEM spec file; if you need another license contact me

## 1.0.12 (2013-10-15)
 * added RSpec tests

## 1.0.11 (2013-09-28)
 * bugfix : fixed issue #18 - fixing issue with last chunk not being properly returned (thanks to Jordan Running)
 * added RSpec tests

## 1.0.10 (2013-06-26)
 * bugfix : fixed issue #14 - passing options along to CSV.parse (thanks to Marcos Zimmermann)

## 1.0.9 (2013-06-19)
 * bugfix : fixed issue #13 with negative integers and floats not being correctly converted (thanks to Graham Wetzler)

## 1.0.8 (2013-06-01)

 * bugfix : fixed issue with nil values in inputs with quote-char (thanks to Félix Bellanger)
 * new options:
    * :force_simple_split : to force simiple splitting on :col_sep character for non-standard CSV-files. e.g. without properly escaped :quote_char
    * :verbose : print out line number while processing (to track down problems in input files)

## 1.0.7 (2013-05-20)

 * allowing process to work with objects with a 'readline' method (thanks to taq)
 * added options:
    * :file_encoding : defaults to utf8  (thanks to MrTin, Paxa)

## 1.0.6 (2013-05-19)

 * bugfix : quoted fields are now correctly parsed

## 1.0.5 (2013-05-08)

 * bugfix : for :headers_in_file option

## 1.0.4 (2012-08-17)

 * renamed the following options:
    * :strip_whitepace_from_values => :strip_whitespace   - removes leading/trailing whitespace from headers and values

## 1.0.3 (2012-08-16)

 * added the following options:
    * :strip_whitepace_from_values   - removes leading/trailing whitespace from values

## 1.0.2 (2012-08-02)

 * added more options for dealing with headers:
    * :user_provided_headers ,user provided Array with header strings or symbols, to precisely define what the headers should be, overriding any in-file headers (default: nil)
    * :headers_in_file , if the file contains headers as the first line (default: true)

## 1.0.1 (2012-07-30)

 * added the following options:
    * :downcase_header
    * :strings_as_keys
    * :remove_zero_values
    * :remove_values_matching
    * :remove_empty_hashes
    * :convert_values_to_numeric

 * renamed the following options:
    * :remove_empty_fields => :remove_empty_values


## 1.0.0 (2012-07-29)

 * renamed `SmarterCSV.process_csv` to `SmarterCSV.process`.

## 1.0.0.pre1 (2012-07-29)
