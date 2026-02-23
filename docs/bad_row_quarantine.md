
### Contents

  * [Introduction](./_introduction.md)
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
  * [**Bad Row Quarantine**](./bad_row_quarantine.md)

--------------

# Bad Row Quarantine

Real-world CSV files are often malformed. By default, SmarterCSV raises an exception on the
first bad row it encounters. The `on_bad_row` option lets you keep processing and handle bad
rows in whatever way suits your application.

## What counts as a bad row

- Malformed CSV (unclosed quoted fields, unterminated multiline rows)
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

### `:skip`

Silently skip bad rows and continue. The count of skipped rows is available on
`reader.errors[:bad_row_count]`. No error records are stored.

```ruby
reader = SmarterCSV::Reader.new('data.csv', on_bad_row: :skip)
result = reader.process

puts "Processed: #{result.size} good rows"
puts "Skipped:   #{reader.errors[:bad_row_count] || 0} bad rows"
```

### `:collect`

Continue processing and store a structured error record for each bad row in
`reader.errors[:bad_rows]`. Requires using `SmarterCSV::Reader` directly (the
`SmarterCSV.process` convenience method discards the reader instance and cannot
return the collected errors).

```ruby
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
error record hash, then processing continues. Useful for streaming errors to a
dead-letter queue, a metrics system, or a separate file.

```ruby
# Log to a dead-letter file
quarantine = File.open('quarantine.csv', 'w')

reader = SmarterCSV::Reader.new('data.csv',
  on_bad_row: ->(rec) { quarantine.puts(rec[:raw_logical_line]) }
)
reader.process
quarantine.close
```

```ruby
# Send to a monitoring system
reader = SmarterCSV::Reader.new('data.csv',
  on_bad_row: ->(rec) { Metrics.increment('csv.bad_rows', tags: { error: rec[:error_class].name }) }
)
reader.process
```

```ruby
# Collect into your own structure
errors = []
reader = SmarterCSV::Reader.new('data.csv',
  on_bad_row: ->(rec) { errors << rec }
)
result = reader.process
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

Bad row data is stored on the `Reader` instance:

| Attribute | Description |
|-----------|-------------|
| `reader.errors[:bad_row_count]` | Total bad rows encountered (all modes) |
| `reader.errors[:bad_rows]` | Array of error records (`:collect` mode only) |

Note: `SmarterCSV.process` (the convenience method) discards the `Reader` instance after
returning. To access `reader.errors`, always instantiate `SmarterCSV::Reader` directly.

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

--------------------
PREVIOUS: [Value Converters](./value_converters.md) | UP: [README](../README.md)
