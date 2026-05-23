
### Contents

  * [Introduction](./_introduction.md)
  * [Migrating from Ruby CSV](./migrating_from_csv.md)
  * [Ruby CSV Pitfalls](./ruby_csv_pitfalls.md)
  * [Parsing Strategy](./parsing_strategy.md)
  * [**The Basic Read API**](./basic_read_api.md)
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
  * [Bad Row Quarantine](./bad_row_quarantine.md)
  * [Warnings](./warnings.md)
  * [Instrumentation Hooks](./instrumentation.md)
  * [Examples](./examples.md)
  * [Real-World CSV Files](./real_world_csv.md)
  * [SmarterCSV over the Years](./history.md)
  * [Release Notes](./releases/1.18.0/changes.md)

--------------

# SmarterCSV Basic API

Let's explore the basic APIs for reading and writing CSV files. There is a simplified API (backwards conpatible with previous SmarterCSV versions) and the full API, which allows you to access the internal state of the reader or writer instance after processing.

## Reading CSV

SmarterCSV has convenient defaults for automatically detecting row and column separators based on the given data. This provides more robust parsing of input files when you have no control over the data, e.g. when users upload CSV files.
Learn more about this [in this section](./row_col_sep.md).

### Simplified Interface

The simplified call to read CSV files is:

      ```
         array_of_hashes = SmarterCSV.process(file_or_input, options)

      ```

To parse a CSV **string** directly (no file needed), use `SmarterCSV.parse`:

      ```
         array_of_hashes = SmarterCSV.parse(csv_string, options)

      ```

This is equivalent to `SmarterCSV.process(StringIO.new(csv_string), options)` and is the
idiomatic replacement for `CSV.parse(str, headers: true, header_converters: :symbol)`.
See [Migrating from Ruby CSV](./migrating_from_csv.md) for a full comparison.

It can also be used with a block. The block always receives an array of hashes and an optional chunk index:

      ```
         SmarterCSV.process(file_or_input, options) do |array_of_hashes|
           # without chunk_size, each yield contains a one-element array (one row)
         end
      ```

or

      ```
         SmarterCSV.process(file_or_input, options) do |array_of_hashes, chunk_index|
            # the chunk_index can be used to track chunks for parallel processing
         end
      ```

When processing batches of rows, use the `chunk_size` option. The block receives an array of up to `chunk_size` hashes per yield:

      ```
         SmarterCSV.process(file_or_input, {chunk_size: 100}) do |array_of_hashes, chunk_index|
            # process one chunk of up to 100 rows of CSV data
            puts "Processing chunk #{chunk_index}..."
         end
      ```

### Full Interface

The simplified API works in most cases, but if you need access to the internal state and detailed results of the CSV-parsing, you should use this form:

      ```
        reader = SmarterCSV::Reader.new(file_or_input, options)
        data = reader.process

        puts reader.raw_headers
      ```
It can also be used with a block. The block always receives an array of hashes and an optional chunk index:

      ```
        reader = SmarterCSV::Reader.new(file_or_input, options)
        data = reader.process do |array_of_hashes, chunk_index|
           # do something here
        end

        puts reader.raw_headers
      ```

This allows you access to the internal state of the `reader` instance after processing.


## Modern Enumerator API — `each`

`Reader#each` is the modern, idiomatic way to read CSV rows one at a time. It always yields a single `Hash` per row and includes `Enumerable`, so every standard Ruby enumerable method works out of the box.

### Simplified form

```ruby
SmarterCSV.each('data.csv', options) do |hash|
  MyModel.upsert(hash)
end
```

### Full form (recommended — retains reader state after processing)

```ruby
reader = SmarterCSV::Reader.new('data.csv', options)

reader.each do |hash|
  MyModel.upsert(hash)
end

puts reader.headers        # accessible after processing
puts reader.errors.inspect
puts reader.warnings       # see [Warnings](./warnings.md)
```

### Returns an Enumerator when called without a block

```ruby
enum = SmarterCSV.each('data.csv', options)
enum.to_a   # => [{ name: "Alice", ... }, { name: "Bob", ... }, ...]
```

### Enumerable methods work directly

Because `Reader` includes `Enumerable`, all standard Ruby enumerable methods work:

```ruby
reader = SmarterCSV::Reader.new('data.csv', options)

# Filter rows
us_users = reader.select { |h| h[:country] == 'US' }

# Transform
names = reader.map { |h| h[:name] }

# Count good rows
reader.count

# Row index (0-based count of successfully parsed rows, excluding bad rows)
reader.each_with_index do |hash, i|
  puts "Row #{i}: #{hash[:name]}"
end

# Free chunking via Enumerable — no chunk_size needed
reader.each_slice(100) do |batch|
  MyModel.insert_all(batch)
end
```

### Lazy evaluation

`lazy` lets you stop early without reading the entire file:

```ruby
# Read only the first 10 rows matching a condition
reader = SmarterCSV::Reader.new('big.csv', options)
result = reader.lazy.select { |h| h[:status] == 'active' }.first(10)
```

### `each` ignores `chunk_size`

If `chunk_size` is set in options, `each` ignores it and always yields individual `Hash` objects. Use [`each_chunk`](./batch_processing.md) for chunked batch processing.

### Interaction with `on_bad_row`

`each` respects all `on_bad_row` options. Bad rows are skipped (or routed to your handler) and never yielded:

```ruby
reader = SmarterCSV::Reader.new('data.csv', on_bad_row: :collect)
reader.each { |hash| MyModel.upsert(hash) }
reader.errors[:bad_rows].each { |rec| puts "Bad row: #{rec[:error_message]}" }
```

### Read-Transform-Write Pipelines

Composing `SmarterCSV.each` with `SmarterCSV.generate` is the idiomatic replacement for Ruby's `CSV.filter` — read CSV, mutate each row, write the result. See [Examples → Filtering and Transforming a CSV File](./examples.md#filtering-and-transforming-a-csv-file) for the full set of patterns (file → file, STDIN → STDOUT, gzip → gzip, header renaming).

---

## Value Transformation Pipeline

After each row is parsed, SmarterCSV applies transformations to field values in this order:

| Step | Option | Default | Description |
|------|--------|---------|-------------|
| 1 | `strip_whitespace` | `true` | Strips leading/trailing whitespace from all values (and headers) at parse time |
| 2 | `nil_values_matching` | `nil` | Sets values matching the regexp to `nil` |
| 3 | `remove_empty_values` | `true` | Removes keys whose value is `nil` or blank |
| 4 | `remove_zero_values` | `false` | Removes keys whose value is numeric zero |
| 5 | `convert_values_to_numeric` | `true` | Converts numeric-looking strings to `Integer` or `Float` |
| 6 | `value_converters` | `nil` | Applies per-key custom converter lambdas or classes |
| 7 | `remove_empty_hashes` | `true` | Drops rows that are entirely empty after all transformations |

> Steps 2–6 run per field, in that order, for every key/value pair in the row.
> `value_converters` receive the value **after** numeric conversion — guard against `Integer`/`Float` input if needed.

See [Data Transformations](./data_transformations.md) and [Value Converters](./value_converters.md) for details.

---

## Header Transformation Pipeline

Before any data rows are processed, the header line passes through these steps:

```
comment_regexp → strip_chars_from_headers → split on col_sep → strip quote_char
    → strip_whitespace → [gsub spaces/dashes→_ → downcase_header]
    → disambiguate_headers → symbolize → key_mapping
```

`user_provided_headers` bypasses the file header and all transformation steps — your array is used as-is.

See [Header Transformations](./header_transformations.md) for the full step-by-step table and options.

---

## Rescue from Exceptions

While SmarterCSV uses sensible defaults to process the most common CSV files, it will raise exceptions if it can not auto-detect `col_sep`, `row_sep`, or if it encounters other problems. Therefore please rescue from `SmarterCSV::Error`, and handle outliers according to your requirements.

If you encounter unusual CSV files, please follow the tips in the Troubleshooting section below. You can use the options below to accommodate for unusual formats.

## Troubleshooting

In case your CSV file is not being parsed correctly, try to examine it in a text editor. For closer inspection  a tool like `hexdump` can help find otherwise hidden control character or byte sequences like [BOMs](https://en.wikipedia.org/wiki/Byte_order_mark).

```
$ hexdump -C spec/fixtures/bom_test_feff.csv
00000000  fe ff 73 6f 6d 65 5f 69  64 2c 74 79 70 65 2c 66  |..some_id,type,f|
00000010  75 7a 7a 62 6f 78 65 73  0d 0a 34 32 37 36 36 38  |uzzboxes..427668|
00000020  30 35 2c 7a 69 7a 7a 6c  65 73 2c 31 32 33 34 0d  |05,zizzles,1234.|
00000030  0a 33 38 37 35 39 31 35  30 2c 71 75 69 7a 7a 65  |.38759150,quizze|
00000040  73 2c 35 36 37 38 0d 0a                           |s,5678..|
```

## Assumptions / Limitations

* By default, quote escaping uses `:auto` mode — SmarterCSV tries backslash-escape (`\"`) first and falls back to RFC 4180 doubled-quotes (`""`). Use `quote_escaping: :double_quotes` or `:backslash` to fix the mode explicitly. See [Parsing Strategy](./parsing_strategy.md).
* Quote characters around fields are expected to be balanced, e.g. valid: `"field"`, invalid: `"field\"`  — an escaped `quote_char` does not denote the end of a field.


## NOTES about File Encodings:
 * if you have a CSV file which contains unicode characters, you can process it as follows:

```ruby
       File.open(filename, "r:bom|utf-8") do |f|
         data = SmarterCSV.process(f);
       end
```
* if the CSV file with unicode characters is in a remote location, similarly you need to give the encoding as an option to the `open` call:
```ruby
       require 'open-uri'
       file_location = 'http://your.remote.org/sample.csv'
       open(file_location, 'r:utf-8') do |f|   # don't forget to specify the UTF-8 encoding!!
         data = SmarterCSV.process(f)
       end
```

----------------

PREVIOUS: [Parsing Strategy](./parsing_strategy.md) | NEXT: [The Basic Write API](./basic_write_api.md) | UP: [README](../README.md)
