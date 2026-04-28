
### Contents

  * [Introduction](./_introduction.md)
  * [Migrating from Ruby CSV](./migrating_from_csv.md)
  * [Ruby CSV Pitfalls](./ruby_csv_pitfalls.md)
  * [Parsing Strategy](./parsing_strategy.md)
  * [The Basic Read API](./basic_read_api.md)
  * [The Basic Write API](./basic_write_api.md)
  * [Batch Processing](././batch_processing.md)
  * [Configuration Options](./options.md)
  * [Row and Column Separators](./row_col_sep.md)
  * [Header Transformations](./header_transformations.md)
  * [Header Validations](./header_validations.md)
  * [Column Selection](./column_selection.md)
  * [Data Transformations](./data_transformations.md)
  * [Value Converters](./value_converters.md)
  * [Bad Row Quarantine](./bad_row_quarantine.md)
  * [**Warnings**](./warnings.md)
  * [Instrumentation Hooks](./instrumentation.md)
  * [Examples](./examples.md)
  * [Real-World CSV Files](./real_world_csv.md)
  * [SmarterCSV over the Years](./history.md)
  * [Release Notes](./releases/1.16.0/changes.md)

--------------

# Warnings

SmarterCSV records auto-detection and configuration warnings into a structured
collection on the Reader, in addition to emitting them to a log sink. This lets
you inspect warnings programmatically (e.g. surface them in dashboards, fail
deploys on unexpected codes) without parsing stderr text.

## Accessing warnings

### Via the Reader API

```ruby
reader = SmarterCSV::Reader.new('data.csv')
reader.process

reader.warnings
# => [
#   { type: :config,   code: :chunk_size_default, severity: :warn,
#     message: "chunk_size not set, defaulting to 100. ...", count: 1 },
#   ...
# ]
```

### Via the class-level API (`SmarterCSV.warnings`)

Mirrors `SmarterCSV.errors`. Returns the warnings from the most recent call to
`process`, `parse`, `each`, or `each_chunk` on the current thread. Cleared at
the start of each new call.

```ruby
SmarterCSV.process('data.csv')
SmarterCSV.warnings.each do |w|
  logger.warn("[#{w[:type]}/#{w[:code]}] #{w[:message]} (×#{w[:count]})")
end
```

> **Note:** `SmarterCSV.warnings` is per-thread (uses `Thread.current`). It is
> safe in multi-threaded environments (Puma, Sidekiq), but **not fiber-safe**.
> If you process CSV files concurrently in fibers (e.g. with `Async`, `Falcon`,
> or manual `Fiber` scheduling), use `SmarterCSV::Reader` directly so warnings
> are scoped to the reader instance.

## Warning record shape

| Field | Description |
|---|---|
| `type` | Coarse semantic grouping. Currently: `:config`, `:deprecation`, `:encoding`, `:row_sep`. |
| `code` | Unique identifier for the specific warning. |
| `severity` | Log level: `:debug` / `:info` / `:warn` / `:error` / `:fatal`. |
| `message` | Human-readable description. |
| `count` | Number of times this `(type, code)` was triggered during the run. |

Repeated warnings of the same `(type, code)` are deduped — `count` tracks
occurrences. The `message` is the first one emitted.

## Available codes

| Code | Type | Severity | Triggered when |
|---|---|---|---|
| `:chunk_size_default` | `:config` | `:warn` | `each_chunk` is called without `chunk_size:` and the default of `100` is used. |
| `:header_a_method` | `:deprecation` | `:warn` | The deprecated `Reader#headerA` accessor is called. |
| `:utf8_missing_binary_mode` | `:encoding` | `:warn` | UTF-8 input is being processed but the IO was not opened with `"b:utf-8"`. |
| `:no_clear_row_sep` | `:row_sep` | `:error` | Auto-detection found a true tie between separators after scanning 64KB. Falls back to `"\n"` — silent miss-parse risk. |
| `:no_row_sep_found` | `:row_sep` | `:error` | No known row separator was found in the first 64KB. Falls back to `"\n"`. Likely an exotic separator like `\u2028`. |

## Log sink routing

When the warning is emitted, the sink is selected at Reader construction time:

* **Rails.logger present** — the warning is routed through `Rails.logger` at
  the declared `severity`. `Rails.logger.warn(...)`, `Rails.logger.error(...)`,
  etc.
* **No Rails.logger** — falls back to `Kernel#warn` (writes to `$stderr`).

Detection is one-shot at construct time, so there is no per-call overhead.

## Suppressing warnings

Pass `verbose: :quiet` to suppress both the recording and the log emission of
all warnings. Currently this affects every code listed above.

```ruby
SmarterCSV.process('data.csv', verbose: :quiet)
SmarterCSV.warnings   # => []
```

> ⚠️ Suppressing `:row_sep` warnings hides genuine silent miss-parse risk on
> ambiguous files. Prefer passing `row_sep:` explicitly over silencing.

----------------

PREVIOUS: [Bad Row Quarantine](./bad_row_quarantine.md) | NEXT: [Instrumentation Hooks](./instrumentation.md) | UP: [README](../README.md)
