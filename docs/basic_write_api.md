
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


Using per-key value converters, you can control how specific hash keys in your data are converted in the output.

Example 1:

```
      options = {
        value_converters: {
          active: ->(v) { !!v ? 'YES' : 'NO' },
        }
      }
```

This maps the boolean value of the hash key `:active` into strings `"YES"`, `"NO"`.

Example 2:

```
      options = {
        value_converters: {
          active: ->(v) { !!v ? '✅' : '❌' },
          balance: ->(v) do
            case v
            when Float
              '$%.2f' % v.round(2)
            when Integer
              "$#{v}"
            else
              v.to_s
            end
          end,
        }
      }
```

This maps the hash key `:balance` to a string. Floats are rounded and displayed with 2 decimals and prefixed by `$`. Integers are prefixed by `$`.
The boolean value of the key `:active` is mapped into an emoji.

### Global Value Converters

You can also use the special keyword `:_all` to define transformations that are applied to each field of the CSV file.

```
      options = {
        value_converters: {        
          disable_auto_quoting: true, # ⚠️ Important: turn off auto-quoting because we're messing with it below
          active: ->(v) { !!v ? 'YES' : 'NO' },
          _all: ->(_k, v) { v.is_a?(String) ? "\"#{v}\"" : v } # only double-quote string fields
        }  
      }
```

Using the `:_all` keyword, you can set up rules to convert all hash keys. This is applied after all per-key conversions are made.

This example puts double-quotes around all String-value data, but leaves other types unchanged.

Note that when you're customizing putting quote-chars around fields, you need to `disable_auto_quoting`.

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
