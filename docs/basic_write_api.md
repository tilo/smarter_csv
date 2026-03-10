
### Contents

  * [Introduction](./_introduction.md)
  * [Migrating from Ruby CSV](./migrating_from_csv.md)
  * [Parsing Strategy](./parsing_strategy.md)
  * [The Basic Read API](./basic_read_api.md)
  * [**The Basic Write API**](./basic_write_api.md)
  * [Batch Processing](././batch_processing.md)
  * [Configuration Options](./options.md)
  * [Row and Column Separators](./row_col_sep.md)
  * [Header Transformations](./header_transformations.md)
  * [Header Validations](./header_validations.md)
  * [Column Selection](./column_selection.md)
  * [Data Transformations](./data_transformations.md)
  * [Value Converters](./value_converters.md)
  * [Bad Row Quarantine](./bad_row_quarantine.md)
  * [Instrumentation Hooks](./instrumentation.md)
  * [Examples](./examples.md)
  * [SmarterCSV over the Years](./history.md)

--------------

# SmarterCSV Basic Write API

Let's explore the basic API for writing CSV files. There is a simplified API (backwards conpatible with previous SmarterCSV versions) and the full API, which allows you to access the internal state of the writer instance after processing.

## Writing CSV Files

To generate a CSV file, we use the `<<` operator to append new data to the file.

The input operator for adding data to a CSV file `<<` can handle single hashes, array-of-hashes, or array-of-arrays-of-hashes, and can be called one or multiple times in order to create a file.

### Hashes, Not Arrays — and Why It Matters for Data Integrity

Ruby's `CSV` library lets you write raw arrays: `csv << ["Alice", 30, "NYC"]`. SmarterCSV
deliberately does not support this, because positional array writing is an open invitation
to silent data corruption.

Consider what happens when a column is added:

```ruby
# Originally:
headers = [:name, :age, :city]

# Later, a column is inserted:
headers = [:name, :age, :country, :city]

# But the array rows were never updated:
csv << ["Alice", 30, "NYC"]    # "NYC" now lands under :country, not :city
csv << ["Bob",   25, "London"] # same silent mis-alignment
```

There is no error. The CSV looks valid. The data is wrong. This class of bug — a silent off-by-one column mis-alignment — is completely undetectable from the output file alone.

SmarterCSV avoids this entirely by requiring hashes, where every value is explicitly bound to its column name:

```ruby
csv << { name: 'Alice', age: 30, city: 'NYC' }
```

Adding or reordering columns cannot silently shift values. A missing key produces an empty
field in the correct column. The mapping is always explicit.

**Providing `headers:` enforces column order.** When you pass `headers:`, the Writer always
outputs columns in exactly that order — regardless of the order keys appear in the hash.
This is the right tool when column order matters:

```ruby
options = { headers: [:country, :city, :name, :age] }

SmarterCSV.generate('output.csv', options) do |csv|
  # Hash key order is irrelevant — output follows the headers order
  csv << { name: 'Alice', age: 30, city: 'NYC',    country: 'USA' }
  csv << { name: 'Bob',   age: 25, city: 'London',  country: 'UK'  }
end

# output:
# country,city,name,age
# USA,NYC,Alice,30
# UK,London,Bob,25
```

This is the correct way to write CSV when column order matters: declare the headers
explicitly and let the Writer enforce them. No positional assumptions, no off-by-one risk.

If you already have data in arrays, convert to hashes first using your headers as keys.
This forces the key-to-column mapping to be explicit and visible at the one place where
it can actually be verified — instead of being implicit in the position of every value:

```ruby
headers = [:name, :age, :city]
rows    = [["Alice", 30, "NYC"], ["Bob", 25, "London"]]

csv_string = SmarterCSV.generate do |csv|
  rows.each { |row| csv << headers.zip(row).to_h }
end
```

### Auto-Discovery of Headers

By default, the `SmarterCSV::Writer` discovers all keys that are present in the input data, and as they become know, appends them to the CSV headers. This ensures that all data will be included in the output CSV file.

If you want to customize the output file, or only include select headers, check the section about Advanced Features below.

### Auto-Quoting of Problematic Values

CSV files use some special characters that are important for the CSV format to function:
* @row_sep : typically `\n` the carriage return
* @col_sep : typically `,` the comma
* @quote_char : typically `"` the double-quote
  
When your data for a given field in a CSV row contains either of these characters, we need to prevent them to break the CSV file format.

`SmarterCSV::Writer` automatically detects if a field contains either of these three characters. If a field contains the `@quote_char`, it will be prefixed by another `@qoute_char` as per CSV conventions.
In either case the corresponding field will be put in double-quotes. 
  

### Simplified Interface

The simplified interface takes a block. The first argument can be:

* **Omitted** — SmarterCSV writes to an internal `StringIO` and returns the CSV as a `String`.
* A **`String`** path — SmarterCSV opens the file and closes it when done.
* A **`Pathname`** (or any object responding to `#to_path`) — treated the same as a String path.
* Any **IO-like object** responding to `#write` (e.g. `StringIO`, an open `File` handle, a
  socket) — SmarterCSV writes to it but does **not** close it; the caller retains ownership.

Passing anything else raises `ArgumentError` immediately.

**Generate a CSV String directly (no file argument):**

```ruby
csv_string = SmarterCSV.generate do |csv|
  csv << { name: 'Alice', age: 30 }
  csv << { name: 'Bob',   age: 25 }
end
# => "name,age\nAlice,30\nBob,25\n"
```

Options can be passed as the first argument when no destination is given:

```ruby
csv_string = SmarterCSV.generate(col_sep: ';', row_sep: "\r\n") do |csv|
  records.each { |r| csv << r }
end
```

**Write to a file by path:**

```ruby
SmarterCSV.generate('output.csv', options) do |csv|
  MyModel.find_in_batches(batch_size: 100) do |batch|
    batch.each { |record| csv << record.attributes }
  end
end
```

**Write to a file using a `Pathname`:**

```ruby
require 'pathname'
SmarterCSV.generate(Pathname('output.csv'), options) do |csv|
  records.each { |r| csv << r }
end
```

**Write to a `StringIO` (e.g. for Rails streaming responses):**

```ruby
io = StringIO.new
SmarterCSV.generate(io) do |csv|
  records.each { |r| csv << r }
end
send_data io.string, type: 'text/csv', filename: 'export.csv'
```

**Write to an already-open file handle:**

```ruby
File.open('output.csv', 'w') do |f|
  SmarterCSV.generate(f) do |csv|
    records.each { |r| csv << r }
  end
end
```

### Full Interface

The full interface gives you direct access to the `Writer` instance, which is useful when you
need to call `finalize` explicitly or inspect the writer's state afterwards.

```ruby
csv_writer = SmarterCSV::Writer.new(file_path_or_io, options)

MyModel.find_in_batches(batch_size: 100) do |batch|
  batch.each { |record| csv_writer << record.attributes }
end

csv_writer.finalize
```

The full interface accepts the same argument types as the simplified interface: a String path,
a `Pathname`, or any IO-like object responding to `#write`.

## Advanced Features: Customizing the Output Format

You can customize the output format through different features.

In the options, you can pass-in either of these parameters to customize your output format.
* `headers`, which limits the CSV headers to just the specified list.
* `map_header`, which maps a given list of Hash keys to custom strings, and limits the CSV headers to just those.
* `value_converters`, which specifies a hash with more advanced value transformations.

### Limited Headers

You can use the `headers` option to limit the CSV headers to only a sub-set of Hash keys from your data.
This will switch-off the automatic detection of headers, and limit the CSV output file to only the CSV headers you provide in this option.


### Mapping Headers

Similar to the `headers` option, you can define `map_headers` in order to rename a given set of Hash keys to some custom strings in order to rename them in the CSV header. This will switch-off the automatic detection of headers.


### Per Key Value Converters

Using per-key value converters, you can control how specific hash keys in your data are
serialized in the output. Each converter is a lambda that receives the field value and
returns the string to write.

**Boolean to string:**

```ruby
SmarterCSV.generate('output.csv', value_converters: { active: ->(v) { v ? 'YES' : 'NO' } }) do |csv|
  csv << { name: 'Alice', active: true  }
  csv << { name: 'Bob',   active: false }
end
# output:
# name,active
# Alice,YES
# Bob,NO
```

**Date/Time formatting:**

```ruby
SmarterCSV.generate('output.csv', value_converters: { created_at: ->(v) { v&.strftime('%Y-%m-%d') } }) do |csv|
  csv << { name: 'Alice', created_at: Time.now }
end
# output:
# name,created_at
# Alice,2026-03-09
```

**Numeric formatting:**

```ruby
balance_converter = ->(v) do
  case v
  when Float   then '$%.2f' % v.round(2)
  when Integer then "$#{v}"
  else              v.to_s
  end
end

SmarterCSV.generate('output.csv', value_converters: { balance: balance_converter }) do |csv|
  csv << { name: 'Alice', balance: 1234.5 }
  csv << { name: 'Bob',   balance: 500    }
end
# output:
# name,balance
# Alice,$1234.50
# Bob,$500
```

**Reusing the same converter across multiple keys:**

```ruby
date_converter = ->(v) { v&.strftime('%Y-%m-%d') }

SmarterCSV.generate('output.csv', value_converters: { created_at: date_converter, updated_at: date_converter }) do |csv|
  csv << { name: 'Alice', created_at: Time.now, updated_at: Time.now }
end
```

### Global Value Converters

The special key `:_all` defines a transformation applied to every field, after any
per-key converters have run. It receives both the key and the value.

**Stripping whitespace from all string fields:**

```ruby
SmarterCSV.generate('output.csv', value_converters: { _all: ->(_k, v) { v.is_a?(String) ? v.strip : v } }) do |csv|
  csv << { name: '  Alice  ', city: ' NYC ' }
end
# output:
# name,city
# Alice,NYC
```

**Combining per-key and global converters** — per-key runs first, `:_all` runs after:

```ruby
options = {
  value_converters: {
    active:   ->(v) { v ? 'YES' : 'NO' },
    _all:     ->(_k, v) { v.to_s.upcase },
  }
}

SmarterCSV.generate('output.csv', options) do |csv|
  csv << { name: 'Alice', city: 'nyc', active: true }
end
# output:
# name,city,active
# ALICE,NYC,YES
```

**Custom quoting with `:_all`** — when taking manual control of quoting, disable
auto-quoting to avoid double-quoting:

```ruby
options = {
  disable_auto_quoting: true,
  value_converters: {
    active: ->(v) { v ? 'YES' : 'NO' },
    _all:   ->(_k, v) { v.is_a?(String) ? "\"#{v}\"" : v },
  }
}
```

> **Note:** `disable_auto_quoting: true` is a top-level option, not part of
> `value_converters:`. Only disable it when you are taking full control of quoting yourself.

## Serializing Dates, Money, and Units

Ruby's default `to_s` is often not enough when writing dates, monetary values, or measured
quantities to CSV. The target format depends on your consumer — a downstream system, a
locale, or a spreadsheet audience. Use `value_converters:` to take explicit control.

### Dates and Times

`Date#to_s` produces ISO 8601 (`2026-03-09`), which is unambiguous and safe as a default.
Use a converter when you need a different format:

```ruby
# ISO 8601 (default to_s — shown for clarity)
iso   = ->(v) { v&.strftime('%Y-%m-%d') }

# US format: MM/DD/YYYY
us    = ->(v) { v&.strftime('%m/%d/%Y') }

# European format: DD.MM.YYYY
eu    = ->(v) { v&.strftime('%d.%m.%Y') }

# Human-readable with time
full  = ->(v) { v&.strftime('%d %b %Y %H:%M') }

SmarterCSV.generate('output.csv', value_converters: { issued_on: eu, expires_at: full }) do |csv|
  csv << { name: 'Alice', issued_on: Date.new(2026, 3, 9), expires_at: Time.now }
end
# output:
# name,issued_on,expires_at
# Alice,09.03.2026,09 Mar 2026 14:32
```

The `&.` safe-navigation operator ensures a `nil` date field produces an empty cell
rather than raising `NoMethodError`.

### Money

`Money#to_s` (from the [`money`](https://github.com/RubyMoney/money) gem) returns the
fractional amount as a string (e.g. `"4450"` for $44.50 stored in cents) — almost never
what a CSV consumer expects. Always use an explicit converter:

```ruby
# Raw decimal amount — most portable, easy to re-import
amount_only = ->(v) { v&.to_d&.to_s }           # "44.50"

# With currency symbol — for human-readable exports
with_symbol = ->(v) { v ? v.format : nil }        # "$44.50", "€44,50" (locale-aware via money gem)

# Amount + currency code — for multi-currency files
with_code   = ->(v) { v ? "#{v.currency.iso_code} #{v.to_d}" : nil }  # "USD 44.50", "EUR 12.00"
```

Choose the right format for your consumer:

```ruby
# Single-currency export (e.g. internal finance tool)
SmarterCSV.generate('export.csv', value_converters: { price: amount_only, tax: amount_only }) do |csv|
  records.each { |r| csv << r }
end

# Multi-currency export (e.g. cross-border invoicing)
SmarterCSV.generate('export.csv', value_converters: { price: with_code, tax: with_code }) do |csv|
  records.each { |r| csv << r }
end
```

> **Tip:** for re-importable CSV files, prefer `amount_only` — a bare decimal is
> unambiguous and can be parsed back without stripping symbols or handling locale-specific
> separators. Reserve `with_symbol` for human-readable exports that will not be re-parsed.

### Unit Conversions

Value converters are not limited to formatting — they can perform any transformation,
including unit conversions. A common case is exporting sensor or weather data that is
stored internally in one unit but must be delivered in another.

**Fahrenheit to Celsius:**

```ruby
f_to_c = ->(v) { v ? ((v - 32) * 5.0 / 9).round(1) : nil }

options = {
  map_headers:      { temperature: :temperature_c },
  value_converters: { temperature: f_to_c },
}

SmarterCSV.generate('weather.csv', options) do |csv|
  csv << { city: 'New York',   temperature: 32  }   # freezing
  csv << { city: 'Phoenix',    temperature: 104 }   # hot
  csv << { city: 'Paris',      temperature: 68  }
end
# output:
# city,temperature_c
# New York,0.0
# Phoenix,40.0
# Paris,20.0
```

The same pattern applies to any unit pair — kilometers to miles, kilograms to pounds,
meters per second to km/h, and so on:

```ruby
miles_to_km = ->(v) { v ? (v * 1.60934).round(2) : nil }
lbs_to_kg   = ->(v) { v ? (v * 0.453592).round(2) : nil }

options = {
  map_headers:      { distance: :distance_km, weight: :weight_kg },
  value_converters: { distance: miles_to_km,  weight: lbs_to_kg  },
}

SmarterCSV.generate('measurements.csv', options) do |csv|
  records.each { |r| csv << r }
end
```

## Handling Nil, Empty, and Missing Values

By default, both `nil` values and empty-string values are written as an empty field.
Use the `write_nil_value:` and `write_empty_value:` options to substitute a different string.

### `write_nil_value`

Specifies the string written when a hash value is `nil`. Defaults to `''` (empty field).

```ruby
SmarterCSV.generate('output.csv', write_nil_value: 'N/A') do |csv|
  csv << { name: 'Alice', score: nil }
  csv << { name: 'Bob',   score: 42   }
end
# output:
# name,score
# Alice,N/A
# Bob,42
```

### `write_empty_value`

Specifies the string written when a hash value is an empty string `''`. Defaults to `''`.
This also applies to **missing keys**: if the row hash does not contain a key that appears
in the headers, the field defaults to `''` and `write_empty_value:` is substituted.

```ruby
SmarterCSV.generate('output.csv', write_empty_value: 'EMPTY') do |csv|
  csv << { name: 'Alice', city: ''    }   # explicit empty string
  csv << { name: 'Bob'                }   # :city key missing entirely
end
# output:
# name,city
# Alice,EMPTY
# Bob,EMPTY
```

### Using both together

```ruby
options = { write_nil_value: 'NULL', write_empty_value: '-' }
SmarterCSV.generate('output.csv', options) do |csv|
  csv << { name: 'Alice', score: nil, city: '' }
end
# output:
# name,score,city
# Alice,NULL,-
```

> **Note:** `write_nil_value:` is applied first. `write_empty_value:` only fires when the
> value is a non-nil empty string, so the two options are independent.

## File Encoding and BOM

### `encoding`

Specifies the encoding used when opening the output file. Only applies when writing to a
file path or `Pathname`; ignored when an IO object is passed in. Defaults to the system
encoding.

**Simple encoding** — sets the external (file) encoding:

```ruby
SmarterCSV.generate('output.csv', encoding: 'UTF-8') do |csv|
  csv << { city: 'Ångström', country: 'Sweden' }
end
```

**Transcoding** — use `'external:internal'` notation to automatically transcode from your
Ruby strings' encoding to the target file encoding. This is Ruby's standard
`File.open` encoding syntax:

```ruby
# Ruby strings are UTF-8; write a Windows-1252 file for legacy consumers.
# Ruby will transcode each string automatically on write.
SmarterCSV.generate('output.csv', encoding: 'Windows-1252:UTF-8') do |csv|
  records.each { |r| csv << r }
end
```

```ruby
# Transcode UTF-8 strings into ISO-8859-1
SmarterCSV.generate('output.csv', encoding: 'ISO-8859-1:UTF-8') do |csv|
  records.each { |r| csv << r }
end
```

> **Note:** Transcoding raises `Encoding::UndefinedConversionError` if a character in your
> data cannot be represented in the target encoding (e.g. a Chinese character written to
> ISO-8859-1). Handle this with a value converter if you need lossy substitution.

### `write_bom`

When `true`, prepends a UTF-8 BOM (`\xEF\xBB\xBF`) to the very beginning of the output.
Defaults to `false`.

A BOM is useful when the CSV will be opened in **Microsoft Excel**, which uses the BOM as a
signal to interpret the file as UTF-8 rather than the system code page. Without a BOM, Excel
may display accented characters and non-Latin scripts as garbage.

```ruby
SmarterCSV.generate('export_for_excel.csv', encoding: 'UTF-8', write_bom: true) do |csv|
  csv << { name: 'Ångström', value: 99 }
end
# The file begins with 0xEF 0xBB 0xBF followed by the header line.
```

> **Note:** Only use `write_bom: true` with UTF-8 output. Adding a UTF-8 BOM to a
> non-UTF-8 file will corrupt it.

## More Examples

Check out the [RSpec tests](../spec/smarter_csv/writer_spec.rb) for more examples.

----------------
PREVIOUS: [The Basic Read API](./basic_read_api.md) | NEXT: [Batch Processing](./batch_processing.md)
