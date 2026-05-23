
### Contents

  * [Introduction](./_introduction.md)
  * [Migrating from Ruby CSV](./migrating_from_csv.md)
  * [Ruby CSV Pitfalls](./ruby_csv_pitfalls.md)
  * [Parsing Strategy](./parsing_strategy.md)
  * [The Basic Read API](./basic_read_api.md)
  * [The Basic Write API](./basic_write_api.md)
  * [Batch Processing](./batch_processing.md)
  * [Slicing & Parallel Processing](./parallel_slicing.md)
  * [Configuration Options](./options.md)
  * [Row and Column Separators](./row_col_sep.md)
  * [Header Transformations](./header_transformations.md)
  * [Header Validations](./header_validations.md)
  * [Column Selection](./column_selection.md)
  * [Data Transformations](./data_transformations.md)
  * [Value Converters](./value_converters.md)
  * [**Bad Row Quarantine**](./bad_row_quarantine.md)
  * [Warnings](./warnings.md)
  * [Instrumentation Hooks](./instrumentation.md)
  * [Examples](./examples.md)
  * [Real-World CSV Files](./real_world_csv.md)
  * [SmarterCSV over the Years](./history.md)
  * [Release Notes](./releases/1.18.0/changes.md)

--------------

# Bad Row Quarantine

Real-world CSV files are often malformed. By default, SmarterCSV raises an exception on the
first bad row it encounters. The `on_bad_row` option lets you keep processing and handle bad
rows in whatever way suits your application.

## What counts as a bad row

- Malformed CSV (unclosed quoted fields, unterminated multiline rows)
- A field that exceeds `field_size_limit` (see [Limiting field size](#limiting-field-size-field_size_limit))
- Extra columns when running in `strict: true` mode
- Any `SmarterCSV::Error` or `EOFError` raised during row parsing

## Options

| Option | Default | Description |
|--------|---------|-------------|
| `on_bad_row` | `:raise` | How to handle a bad row: `:raise`, `:skip`, `:collect`, or a callable |
| `collect_raw_lines` | `true` | Include `raw_logical_line` in the error record |
| `bad_row_limit` | `nil` | Raise `SmarterCSV::TooManyBadRows` after this many bad rows |

## Modes

### `:raise` (default)

Current behavior — the exception propagates and processing stops:

```ruby
SmarterCSV.process('data.csv')
# => raises SmarterCSV::MalformedCSV on the first bad row
```

The `on_bad_row` option controls what happens when a bad row is encountered:

* `on_bad_row: :raise` (default) fails fast.
* `on_bad_row: :collect` quarantines them — error records available via `SmarterCSV.errors` or `reader.errors`.
* `on_bad_row: ->(rec) { ... }` calls your lambda per bad row — works with both `SmarterCSV.process` and `SmarterCSV::Reader`.
* `on_bad_row: :skip` discards bad rows silently — count available via `SmarterCSV.errors` or `reader.errors`.

### `:collect`

Continue processing and store a structured error record for each bad row.
Error records are available via `SmarterCSV.errors[:bad_rows]` (class-level API)
or `reader.errors[:bad_rows]` (Reader API).

```ruby
# Class-level API — use SmarterCSV.errors after the call
good_rows = SmarterCSV.process('data.csv', on_bad_row: :collect)

good_rows.each { |row| MyModel.create!(row) }

SmarterCSV.errors[:bad_rows].each do |rec|
  Rails.logger.warn "Bad row at line #{rec[:csv_line_number]}: #{rec[:error_message]}"
  Rails.logger.warn "Raw content: #{rec[:raw_logical_line]}"
end
```

```ruby
# Reader API — use when you also need access to headers or other reader state
reader = SmarterCSV::Reader.new('data.csv', on_bad_row: :collect)
result = reader.process

result.each { |row| MyModel.create!(row) }

reader.errors[:bad_rows].each do |rec|
  Rails.logger.warn "Bad row at line #{rec[:csv_line_number]}: #{rec[:error_message]}"
  Rails.logger.warn "Raw content: #{rec[:raw_logical_line]}"
end
```

### Callable (lambda / proc)

Pass any object that responds to `#call`. It is invoked once per bad row with the
error record hash, then processing continues. Because the lambda receives errors
inline, **this works with both `SmarterCSV.process` and `SmarterCSV::Reader`** —
you do not need a `Reader` instance to handle bad rows.

```ruby
# Works with SmarterCSV.process — no Reader instance needed
bad_rows = []
good_rows = SmarterCSV.process('data.csv',
  on_bad_row: ->(rec) { bad_rows << rec })
```

```ruby
# Log to a dead-letter file
quarantine = File.open('quarantine.csv', 'w')
SmarterCSV.process('data.csv',
  on_bad_row: ->(rec) { quarantine.puts(rec[:raw_logical_line]) })
quarantine.close
```

```ruby
# Send to a monitoring system
SmarterCSV.process('data.csv',
  on_bad_row: ->(rec) { Metrics.increment('csv.bad_rows', tags: { error: rec[:error_class].name }) })
```

### `:skip`

Silently skip bad rows and continue. The count of skipped rows is available via
`SmarterCSV.errors[:bad_row_count]` (class-level API) or `reader.errors[:bad_row_count]`
(Reader API). No error records are stored.

```ruby
# Class-level API — use SmarterCSV.errors after the call
SmarterCSV.process('data.csv', on_bad_row: :skip)
puts "Skipped: #{SmarterCSV.errors[:bad_row_count] || 0} bad rows"
```

```ruby
# Reader API — access reader.errors directly
reader = SmarterCSV::Reader.new('data.csv', on_bad_row: :skip)
result = reader.process

puts "Processed: #{result.size} good rows"
puts "Skipped:   #{reader.errors[:bad_row_count] || 0} bad rows"
```

## Error record structure

Each error record is a Hash:

```ruby
{
  csv_line_number:     3,                               # logical row (counting header as row 1)
  file_line_number:    3,                               # physical file line where the row started
  file_lines_consumed: 1,                               # physical lines spanned (>1 for multiline)
  error_class:         SmarterCSV::HeaderSizeMismatch,  # exception class object
  error_message:       "extra columns detected ...",    # exception message string
  raw_logical_line:    "Jane,25,Boston,EXTRA_DATA\n",   # present when collect_raw_lines: true (default)
}
```

### `collect_raw_lines`

`collect_raw_lines: true` (default) — `raw_logical_line` is always included in the error
record. Set to `false` if you want to reduce memory usage and don't need the raw content:

```ruby
reader = SmarterCSV::Reader.new('data.csv',
  on_bad_row: :collect,
  collect_raw_lines: false,
)
```

For multiline rows (quoted fields spanning several physical lines), `raw_logical_line` contains
the fully stitched content — it may include embedded newline characters. The
`file_lines_consumed` field tells you how many physical lines were read.

## Limiting bad rows with `bad_row_limit`

To abort processing after too many failures, set `bad_row_limit`. This works with `:skip`,
`:collect`, and callable modes:

```ruby
reader = SmarterCSV::Reader.new('data.csv',
  on_bad_row: :collect,
  bad_row_limit: 10,
)

begin
  result = reader.process
rescue SmarterCSV::TooManyBadRows => e
  puts "Aborting: #{e.message}"
  puts "Collected so far: #{reader.errors[:bad_rows].size} bad rows"
end
```

## Accessing errors

There are two ways to access bad row data after processing:

### Via `SmarterCSV.errors` (class-level API)

`SmarterCSV.errors` returns the errors from the most recent call to `process`, `parse`,
`each`, or `each_chunk` on the current thread. It is cleared at the start of each new call.

```ruby
SmarterCSV.process('data.csv', on_bad_row: :skip)
puts SmarterCSV.errors[:bad_row_count]   # => 3

SmarterCSV.process('data.csv', on_bad_row: :collect)
puts SmarterCSV.errors[:bad_row_count]   # => 3
puts SmarterCSV.errors[:bad_rows].size   # => 3
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

### Via `reader.errors` (Reader API)

For full control — including access to headers, raw headers, and errors from a specific
call — use `SmarterCSV::Reader` directly:

| Attribute | Description |
|-----------|-------------|
| `reader.errors[:bad_row_count]` | Total bad rows encountered (all modes) |
| `reader.errors[:bad_rows]` | Array of error records (`:collect` mode only) |

```ruby
reader = SmarterCSV::Reader.new('data.csv', on_bad_row: :collect)
reader.process
puts reader.errors[:bad_row_count]
puts reader.headers.inspect
```

## Chunked processing

Bad row quarantine works seamlessly with `chunk_size`. Skipped rows are simply not added to the
current chunk — chunk sizes remain consistent:

```ruby
reader = SmarterCSV::Reader.new('large_file.csv',
  chunk_size: 500,
  on_bad_row: :collect,
)
reader.process do |chunk, index|
  MyModel.import(chunk)
end
puts "Bad rows: #{reader.errors[:bad_row_count]}"
```

## Limiting field size: `field_size_limit`

Real-world CSV files sometimes contain unexpectedly large fields — either intentionally
(a DoS attempt) or accidentally (a forgotten closing quote, a JSON blob in a cell, a notes
field that ran away). Without a limit, SmarterCSV will happily stitch together physical lines
until it either finds the closing quote or reaches end-of-file, potentially consuming hundreds
of megabytes.

`field_size_limit` sets a hard cap (in bytes) on the size of any individual extracted field.
The default is `nil` (no limit). When a field exceeds the limit a
`SmarterCSV::FieldSizeLimitExceeded` exception is raised — and because it inherits from
`SmarterCSV::Error`, the `on_bad_row` option handles it exactly like any other parse error.

### The three cases it prevents

**1. Huge inline field** — a single-line field containing a large payload (e.g. a JSON blob,
a base64-encoded file, or a runaway notes column):

```csv
id,payload
1,"{... 500 KB of JSON ...}"
```

**2. Quoted field spanning many embedded newlines** — a legitimate multiline field in a
poorly exported file that happens to be enormous:

```csv
ticket_id,notes
42,"Customer wrote:
... (thousands of lines of chat history) ...
"
```

**3. Never-closing quoted field** — a missing closing quote causes the parser to stitch every
subsequent physical line into one logical row until EOF:

```csv
id,comment
1,"this quote never closes
2,this entire row is now inside the field
3,and this one too ...
```

Without `field_size_limit`, case 3 reads the entire rest of the file into memory. With the
limit set, the stitch loop raises `FieldSizeLimitExceeded` as soon as the accumulating buffer
crosses the threshold.

### Usage

```ruby
# Raise immediately on any oversized field (default on_bad_row: :raise)
SmarterCSV.process('data.csv', field_size_limit: 1_000_000)  # 1 MB per field

# Skip oversized rows and continue
SmarterCSV.process('data.csv', field_size_limit: 1_000_000, on_bad_row: :skip)

# Collect oversized rows for inspection
reader = SmarterCSV::Reader.new('data.csv',
  field_size_limit: 1_000_000,
  on_bad_row: :collect,
)
result = reader.process
reader.errors[:bad_rows].each do |rec|
  Rails.logger.warn "Oversized field on row #{rec[:csv_line_number]}: #{rec[:error_message]}"
end
```

### What "bytes" means here

The limit is checked against `String#bytesize` (raw byte count), not character count.
For ASCII content they are identical. For multi-byte UTF-8 content (e.g. CJK characters)
bytesize is larger than the character count — so the limit is a memory cap, not a
character cap, which is what matters for DoS protection.

### Performance

`field_size_limit` is zero-overhead when not set (the default `nil` short-circuits all
checks). When set, a single integer comparison is performed per logical row; the per-field
scan only runs when the raw line is large enough to potentially contain an oversized field.
Normal rows (where the entire line fits within the limit) bypass per-field checking entirely.

--------------------

PREVIOUS: [Value Converters](./value_converters.md) | NEXT: [Warnings](./warnings.md) | UP: [README](../README.md)
