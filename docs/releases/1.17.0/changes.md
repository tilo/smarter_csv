
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

RSpec tests: **1,434 → 2,201** (+767 tests since 1.16.4)

1.17.0 is a **features-and-quality** release, focused on three things: streaming IO inputs, a structured warnings system, and Rails-friendly defaults. The C parser's core line-parsing — separator splitting, quote/escape handling, multiline stitching — is unchanged from 1.16.0 (see [`docs/releases/1.16.0/`](../1.16.0/changes.md) for the parser performance story); what changed in the C path this cycle is a faster code path for quoted-field-heavy files and Unicode-aware blank detection. On the C-accelerated path, 1.17.0 vs 1.16.4 is a **mixed picture**: quoted-field-heavy and wide files run meaningfully faster, a handful of short-line / many-small-field files run a little slower, and the rest are within noise. The Ruby path is parity throughout. The wins come from the faster quoted-field handling; the small regressions trace to the new auto-detection default (`auto_row_sep_chars` 500→4096) plus a tiny per-line overhead — see [performance_notes.md](performance_notes.md) and [benchmarks.md](benchmarks.md) for the per-file breakdown.

---

## Compatibility

* **No breaking changes.** All 1.16.x code continues to work without modification.
* **Behavior change worth noting:** `auto_row_sep_chars: nil` / `0` no longer means "scan whole file" — these values fall back to the default with a warning. The total scan is hard-capped at 64KB. If you relied on the previous undocumented "scan whole file" semantics, this is a visible change.

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

* **`auto_row_sep_chars` default changed to `4096`** (was `500` in 1.16.x). Sized to cover wide-header CSVs in a single read. Out-of-range values, `nil`, or `0` fall back to the default with a warning. **Behavior change vs 1.16.x:** the previous undocumented "scan whole file" semantics on `nil`/`0` is removed; the total scan is hard-capped at 64KB.

* **`buffer_size` is now a public option** — peek buffer chunk size for non-seekable inputs (pipes, gzip readers, HTTP/S3 bodies). Default `16_384`. Out-of-range values warn and clamp to the supported range rather than raising. Has no effect on seekable inputs (file paths, `File`, `StringIO`).

* **Files ending in a lone `\r`** are now correctly detected as `\r`-terminated instead of falling through to a "no clear row separator" warning.

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
