
### Contents

  * [Introduction](../../_introduction.md)
  * [Migrating from Ruby CSV](../../migrating_from_csv.md)
  * [Ruby CSV Pitfalls](../../ruby_csv_pitfalls.md)
  * [Parsing Strategy](../../parsing_strategy.md)
  * [The Basic Read API](../../basic_read_api.md)
  * [The Basic Write API](../../basic_write_api.md)
  * [Batch Processing](../../batch_processing.md)
  * [Configuration Options](../../options.md)
  * [Row and Column Separators](../../row_col_sep.md)
  * [Header Transformations](../../header_transformations.md)
  * [Header Validations](../../header_validations.md)
  * [Column Selection](../../column_selection.md)
  * [Data Transformations](../../data_transformations.md)
  * [Value Converters](../../value_converters.md)
  * [Bad Row Quarantine](../../bad_row_quarantine.md)
  * [Warnings](../../warnings.md)
  * [Instrumentation Hooks](../../instrumentation.md)
  * [Examples](../../examples.md)
  * [Real-World CSV Files](../../real_world_csv.md)
  * [SmarterCSV over the Years](../../history.md)
  * [**Release Notes**](./changes.md)

--------------

# SmarterCSV 1.17.0 — Changes

RSpec tests: **1,434 → 1,905+** (+471 tests since 1.16.4)

1.17.0 is a **features-and-quality** release, focused on three things: streaming IO inputs, a structured warnings system, and Rails-friendly defaults. The C parser hot path is unchanged from 1.16.0 (see [`docs/releases/1.16.0/`](../1.16.0/changes.md) for the parser performance story). On the C-accelerated path, 1.17.0 vs 1.16.4 is a **mixed picture**: 5 files run 6.7%–15.5% faster (long-quoted-field and wide files), 3 files run 8.8%–14.4% slower (short-line / many-small-field files), and 11 are within noise. The Ruby path is parity throughout. The mixed pattern traces to the new auto-detection defaults (`auto_row_sep_chars` 500→8192) — see [performance_notes.md](performance_notes.md) and [benchmarks.md](benchmarks.md) for the per-file breakdown.

---

## Compatibility

* **No breaking changes.** All 1.16.x code continues to work without modification.
* **Behavior change worth noting:** `auto_row_sep_chars: nil` / `0` no longer means "scan whole file" — values below `8192` fall back to the default `8192` with a warning. The hard cap on `guess_line_ending` is now 64KB. If you relied on the previous undocumented "scan whole file" semantics, this is a visible change.

---

## Headline Features

### 1. Non-Seekable Streaming Inputs

SmarterCSV now reads directly from any IO source — including streams that don't support `rewind` or `seek`. No need to materialize the file on disk first.

```ruby
# Gzipped CSV — stream-decompressed, never written to disk
require 'zlib'
Zlib::GzipReader.open('huge.csv.gz') do |io|
  SmarterCSV.process(io) { |row| MyModel.upsert(row.first) }
end

# STDIN / pipes
SmarterCSV.process($stdin) { |row, _| MyModel.upsert(row.first) }

# HTTP response body
require 'open-uri'
URI.open('https://example.com/data.csv') { |io| SmarterCSV.process(io) }

# S3 — stream the response body directly
require 'aws-sdk-s3'
obj = Aws::S3::Client.new.get_object(bucket: 'data', key: 'imports/users.csv')
SmarterCSV::Reader.new(obj.body, chunk_size: 500).each_chunk do |chunk, _|
  MyModel.insert_all(chunk)
end
```

Auto-detection of `row_sep` and `col_sep` works on these streaming sources thanks to internal buffering — the underlying source never needs to support `rewind` or `seek`. See [Real-World CSV Files → I/O Patterns](../../real_world_csv.md#io-patterns) and [Examples → Streaming Inputs](../../examples.md#example-14-streaming-inputs-non-seekable-io).

### 2. Structured Warnings Collection

Auto-detection and configuration warnings are now collected on the Reader as a deduped histogram, in addition to being emitted to a log sink:

```ruby
reader = SmarterCSV::Reader.new('data.csv')
reader.process
reader.warnings
# => [
#   { type: :config, code: :chunk_size_default, severity: :warn,
#     message: "chunk_size not set, defaulting to 100. ...", count: 1 },
#   ...
# ]
```

Repeated warnings of the same `(type, code)` are deduped — `count` tracks occurrences across the run. This lets you surface warnings programmatically (dashboards, fail-deploys-on-codes, etc.) without parsing stderr text.

**Warning codes available in 1.17.0:**

| Code                          | Type           | Severity | Triggered when                                                                                |
|-------------------------------|----------------|----------|-----------------------------------------------------------------------------------------------|
| `:chunk_size_default`         | `:config`      | `:warn`  | `each_chunk` is called without `chunk_size:` and the default of `100` is used.                |
| `:header_a_method`            | `:deprecation` | `:warn`  | The deprecated `Reader#headerA` accessor is called.                                           |
| `:utf8_missing_binary_mode`   | `:encoding`    | `:warn`  | UTF-8 input is being processed but the IO was not opened with `"b:utf-8"`.                    |
| `:no_clear_row_sep`           | `:row_sep`     | `:error` | Auto-detection found a true tie between separators after scanning 64KB. Silent miss-parse risk. |
| `:no_row_sep_found`           | `:row_sep`     | `:error` | No known row separator was found in the first 64KB. Likely an exotic separator like ` `. |

See [Warnings](../../warnings.md) for the full record shape, suppression options, and Rails integration details.

### 3. Class-Level `SmarterCSV.warnings` Accessor

Mirrors `SmarterCSV.errors`. Returns warnings from the most recent call to `process`, `parse`, `each`, or `each_chunk` on the current thread. Cleared at the start of each new call.

```ruby
SmarterCSV.process('data.csv')
SmarterCSV.warnings.each do |w|
  logger.warn("[#{w[:type]}/#{w[:code]}] #{w[:message]} (×#{w[:count]})")
end
```

Per-thread (uses `Thread.current`) — safe under Puma and Sidekiq. Not fiber-safe; use `SmarterCSV::Reader` directly if processing CSV concurrently with `Async`/`Falcon`/manual `Fiber` scheduling.

### 4. Rails.logger Auto-Routing

When `Rails.logger` is present, warnings are routed through it at the severity declared at the call site (`:debug` / `:info` / `:warn` / `:error` / `:fatal`):

```
# In log/development.log
[WARN]  SmarterCSV: chunk_size not set, defaulting to 100. ...
```

Without Rails, falls back to `Kernel#warn` (writes to `$stderr`). Detection is one-shot at Reader construction — no per-call overhead. The programmatic `reader.warnings` collection is identical in both modes.

See [Warnings → Log sink routing](../../warnings.md#log-sink-routing).

---

## Improvements

* **Better auto-detection of `row_sep` and `col_sep`** — more accurate results on files with comment headers and other irregularities at the start of the stream.

* **`auto_row_sep_chars` default and semantics** — defaults to `512` (was `500`). Now means **"initial scan chunk size"** for the adaptive doubling loop in `guess_line_ending`, not the per-iteration chunk size. Validated to `[512, 65_536]` = `[MIN_AUTO_ROW_SEP_CHARS, MAX_AUTO_ROW_SEP_CHARS]`. Out-of-range values, `nil`, or `0` are rejected and fall back to the default with a warning. **Behavior change vs 1.16.x:** the previous undocumented "scan whole file" semantics on `nil`/`0` is removed; the new total scan is hard-capped at 64KB.

* **`guess_line_ending` adaptive doubling scan** — first read is `auto_row_sep_chars` bytes (default 512); iter 2 reuses the same size; iter 3+ doubles each iteration up to `MAX_AUTO_ROW_SEP_CHARS`. Common files (clear separator within the first ~50 bytes) resolve at iter 1 with only 512 bytes of regex scan. Ambiguous files (wide headers, comment preambles) escalate naturally. Read pattern with default `auto_row_sep_chars: 512`: `512 → 512 → 1024 → 2048 → 4096 → 8192 → 16384 → 32768` (loop ends at MAX_AUTO_SCAN = 64KB). See [performance_notes.md](performance_notes.md).

* **`buffer_size` is now a public option** — peek buffer chunk size for non-seekable inputs (pipes, gzip readers, HTTP/S3 bodies). Default `16_384` (one EBS gp3 I/O block; one Apple Silicon VM page). Validated and clamped to `[MIN_BUFFER_SIZE, MAX_BUFFER_SIZE]` = `[4096, 65_536]`; out-of-range values warn and clamp to the boundary rather than raising. If `buffer_size < auto_row_sep_chars`, bumps to `max(2 × buffer_size, MIN_AUTO_ROW_SEP_CHARS)`. Has no effect on seekable inputs (file paths, `File`, `StringIO`).

* **New constants** *(pre6)* — `SmarterCSV::PeekableIO::{MIN,MAX}_BUFFER_SIZE` (4096, 65_536) and `SmarterCSV::AutoDetection::{MIN,MAX}_AUTO_ROW_SEP_CHARS` (512, 65_536). `DEFAULT_OPTIONS[:auto_row_sep_chars]` and `DEFAULT_OPTIONS[:buffer_size]` reference these constants directly. Validation logic references the constants too, so test scenarios can use `stub_const` to exercise sub-floor behavior in PeekableIO unit tests.

* **`SmarterCSV.errors` mid-stream preservation** *(merged from 1.16.4)* — fixed a bug where collected error records could be lost when processing raised mid-stream (e.g. `bad_row_limit:` exceeded → `TooManyBadRows`, or a user block raising through `.process` / `.each` / `.each_chunk`).

* **`enforce_utf8_encoding` for `ASCII-8BIT` inputs** *(merged from 1.16.4)* — fixed incorrect replacement of all non-ASCII bytes when the input was tagged binary. Encoding is now relabeled to UTF-8 before transcoding so only genuinely invalid byte sequences are replaced.

---

## Documentation

Substantive expansion of the user-facing docs to match the new capabilities:

* **`docs/examples.md`** — six new cookbook entries (Examples 14–19): Streaming Inputs, Resumable Plain-Ruby Import, CSV Files with Comment Lines, Tab-Separated Values (TSV), Multi-Line Fields, and Filtering and Transforming a CSV File (the `CSV.filter` replacement pattern).
* **`docs/real_world_csv.md`** — expanded I/O Patterns section with worked examples for gzip, S3, HTTP, STDIN, and `IO.popen`. Added a Multi-Line Quoted Fields worked example.
* **`docs/warnings.md`** *(new)* — full coverage of the structured warnings system: record shape, available codes, log-sink routing for Rails vs non-Rails, suppression via `verbose: :quiet`.
* **`docs/header_transformations.md`** — added a worked example for `comment_regexp:` (CSV files with comment lines).
* **`docs/row_col_sep.md`** — added a worked TSV example.
* **`docs/batch_processing.md`** — added a Resumable Import (Plain Ruby) example using `chunk_index` + a JSON state file (companion to the Rails 8.1 ActiveJob version in `examples.md`).
* **`docs/basic_read_api.md`** / **`docs/basic_write_api.md`** — cross-references to the read-transform-write composition pattern; added `$stdout` and S3 streaming write examples.
* **`README.md`** — added inline examples for streaming inputs, value converters, header validation, and writing CSV; one-sentence note on Rails.logger auto-routing.

---

PREVIOUS: [SmarterCSV over the Years](../../history.md) | UP: [README](../../../README.md)
