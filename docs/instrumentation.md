### Contents

  * [Introduction](./_introduction.md)
  * [Migrating from Ruby CSV](./migrating_from_csv.md)
  * [Parsing Strategy](./parsing_strategy.md)
  * [The Basic Read API](./basic_read_api.md)
  * [The Basic Write API](./basic_write_api.md)
  * [Batch Processing](./batch_processing.md)
  * [Configuration Options](./options.md)
  * [Row and Column Separators](./row_col_sep.md)
  * [Header Transformations](./header_transformations.md)
  * [Header Validations](./header_validations.md)
  * [Column Selection](./column_selection.md)
  * [Data Transformations](./data_transformations.md)
  * [Value Converters](./value_converters.md)
  * [Bad Row Quarantine](./bad_row_quarantine.md)
  * [**Instrumentation Hooks**](./instrumentation.md)
  * [Examples](./examples.md)
  * [SmarterCSV over the Years](./history.md)

--------------

# Instrumentation Hooks

SmarterCSV provides three optional callback hooks so you can observe file processing
without wrapping every call site in timing code. The hooks work with `SmarterCSV.process`
(library-controlled iteration). Enumerator modes (`each`, `each_chunk`) do not fire
hooks — in those modes the caller owns the lifecycle and should instrument their own loop.

## The Three Hooks

| Hook          | Fires when                                          | Useful for                                  |
|---------------|-----------------------------------------------------|---------------------------------------------|
| `on_start`    | Once, before the first row is parsed                | Logging intent, starting timers, counters   |
| `on_chunk`    | After each chunk is parsed, before block runs       | Progress tracking, per-batch metrics        |
| `on_complete` | Once, after the entire file is exhausted            | Total duration, row counts, summary metrics |

`on_chunk` only fires when `chunk_size` is set. In non-chunked mode only `on_start` and
`on_complete` fire.

## Usage

All three hooks are lambdas (or any callable) passed as options:

```ruby
SmarterCSV.process('data.csv',
  chunk_size: 500,

  on_start: ->(info) {
    Rails.logger.info "Starting CSV import: #{info[:input]} (#{info[:file_size]} bytes)"
    Metrics.increment('csv.import.start')
  },

  on_chunk: ->(info) {
    Rails.logger.debug "Chunk #{info[:chunk_number]}: #{info[:rows_in_chunk]} rows " \
                       "(#{info[:total_rows_so_far]} so far)"
  },

  on_complete: ->(stats) {
    Rails.logger.info "Import complete: #{stats[:total_rows]} rows in #{stats[:duration].round(2)}s"
    Metrics.histogram('csv.import.duration', stats[:duration])
    Metrics.gauge('csv.import.rows', stats[:total_rows])
    Metrics.increment('csv.import.bad_rows', stats[:bad_rows]) if stats[:bad_rows] > 0
  },
) { |chunk| MyModel.insert_all(chunk) }
```

## Hook Payloads

### `on_start`

| Key          | Type          | Description                                                         |
|--------------|---------------|---------------------------------------------------------------------|
| `:input`     | String        | File path if input is a filename; class name (e.g. `"File"`) otherwise |
| `:file_size` | Integer / nil | File size in bytes if determinable; nil for IO objects              |
| `:col_sep`   | String        | Effective column separator (after auto-detection)                   |
| `:row_sep`   | String        | Effective row separator (after auto-detection)                      |

### `on_chunk`

| Key                   | Type    | Description                                          |
|-----------------------|---------|------------------------------------------------------|
| `:chunk_number`       | Integer | 1-based index of this chunk                          |
| `:rows_in_chunk`      | Integer | Number of rows in this chunk (≤ `chunk_size`)        |
| `:total_rows_so_far`  | Integer | Cumulative rows processed including this chunk       |

### `on_complete`

| Key             | Type    | Description                                                        |
|-----------------|---------|--------------------------------------------------------------------|
| `:total_rows`   | Integer | Total rows successfully parsed                                     |
| `:total_chunks` | Integer | Number of chunks yielded (0 in non-chunked mode)                   |
| `:duration`     | Float   | Elapsed seconds from `on_start` to `on_complete`                   |
| `:bad_rows`     | Integer | Number of rows that triggered `on_bad_row` handling (0 if none)    |

## Non-chunked mode

When `chunk_size` is not set, `on_chunk` never fires. `on_start` and `on_complete`
still fire and give you the full-file summary:

```ruby
SmarterCSV.process('data.csv',
  on_start:    ->(info)  { @started_at = Time.now; log "Importing #{info[:input]}" },
  on_complete: ->(stats) { log "Done: #{stats[:total_rows]} rows in #{stats[:duration].round(3)}s" },
)
```

## Execution order

```
on_start
  ├─ on_chunk (chunk 1 parsed) → block runs → returns
  ├─ on_chunk (chunk 2 parsed) → block runs → returns
  └─ on_chunk (chunk N parsed) → block runs → returns
on_complete
```

`on_chunk` fires **before** the block receives the chunk, so you can record timing or
state before your processing logic runs.

## Without Rails / ActiveSupport

The hooks are plain callables — no dependency on Rails or any framework:

```ruby
require 'logger'
logger = Logger.new($stdout)

SmarterCSV.process('import.csv',
  on_start:    ->(i) { logger.info  "CSV import started: #{i[:input]}" },
  on_complete: ->(s) { logger.info  "CSV import done: #{s[:total_rows]} rows, #{s[:duration].round(2)}s" },
)
```

## With `ActiveSupport::Notifications` (Rails)

If you prefer Rails-style instrumentation, wrap the hooks yourself:

```ruby
# config/initializers/smarter_csv_instrumentation.rb
ON_START = ->(info) {
  ActiveSupport::Notifications.instrument('start.smarter_csv', info)
}
ON_COMPLETE = ->(stats) {
  ActiveSupport::Notifications.instrument('complete.smarter_csv', stats)
}

# Subscribe once at startup:
ActiveSupport::Notifications.subscribe('complete.smarter_csv') do |*, payload|
  StatsD.histogram('csv.duration', payload[:duration])
  StatsD.gauge('csv.rows', payload[:total_rows])
end
```

Then pass the cached lambdas to any `process` call:

```ruby
SmarterCSV.process(file, on_start: ON_START, on_complete: ON_COMPLETE)
```

--------------------
PREVIOUS: [Bad Row Quarantine](./bad_row_quarantine.md) | NEXT: [Examples](./examples.md) | UP: [README](../README.md)
