
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
  * [Warnings](./warnings.md)
  * [Instrumentation Hooks](./instrumentation.md)
  * [**Examples**](./examples.md)
  * [Real-World CSV Files](./real_world_csv.md)
  * [SmarterCSV over the Years](./history.md)
  * [Release Notes](./releases/1.16.0/changes.md)

--------------

# Examples

**Rescue from `SmarterCSV::Error` (recommended):** SmarterCSV auto-detects row and column separators. In rare cases detection fails and raises an exception (e.g. `NoColSepDetected`). Rescuing from `SmarterCSV::Error` ensures your application handles unexpected CSV formats gracefully.

---

1. [CSV → Array of Hashes](#example-1-csv--array-of-hashes)
2. [Parsing a CSV String](#example-2-parsing-a-csv-string)
3. [Key Mapping and Column Selection](#example-3-key-mapping-and-column-selection)
4. [Encoding and Preamble Skip](#example-4-encoding-and-preamble-skip)
5. [Value Converters](#example-5-value-converters)
6. [Header Validation](#example-6-header-validation)
7. [Bad Row Handling](#example-7-bad-row-handling)
8. [Writing CSV](#example-8-writing-csv)
9. [Using `each` and `each_chunk` Enumerators](#example-9-using-each-and-each_chunk-enumerators)
10. [Importing into a Database](#example-10-importing-into-a-database)
11. [Batch Processing with Sidekiq](#example-11-batch-processing-with-sidekiq)
12. [Resumable CSV Import with Rails ActiveJob](#example-12-resumable-csv-import-with-rails-activejob-rails-81)
13. [Instrumentation](#example-13-instrumentation)
14. [Streaming Inputs (Non-Seekable IO)](#example-14-streaming-inputs-non-seekable-io)
15. [Resumable Import (Plain Ruby)](#example-15-resumable-import-plain-ruby)
16. [CSV Files with Comment Lines](#example-16-csv-files-with-comment-lines)
17. [Tab-Separated Values (TSV)](#example-17-tab-separated-values-tsv)
18. [Multi-Line Fields](#example-18-multi-line-fields)

---

## Example 1: CSV → Array of Hashes

Each hash only contains keys for columns with non-nil, non-empty values — columns with blank entries are omitted automatically:

```ruby
$ cat pets.csv
first name,last name,dogs,cats,birds,fish
Dan,McAllister,2,,,
Lucy,Laweless,,5,,
Miles,O'Brian,,,,21
Nancy,Homes,2,,1,

$ irb
> require 'smarter_csv'
> pets_by_owner = SmarterCSV.process('pets.csv')
 => [ {first_name: "Dan",   last_name: "McAllister", dogs: 2},
      {first_name: "Lucy",  last_name: "Laweless",   cats: 5},
      {first_name: "Miles", last_name: "O'Brian",    fish: 21},
      {first_name: "Nancy", last_name: "Homes",      dogs: 2, birds: 1}
    ]
```

---

## Example 2: Parsing a CSV String

Use `SmarterCSV.parse` to parse a CSV string directly — no file needed. Useful in tests, API responses, or when the CSV arrives as a string in memory:

```ruby
csv_string = <<~CSV
  name,age,city
  Alice,30,New York
  Bob,25,Chicago
CSV

data = SmarterCSV.parse(csv_string)
# => [{name: "Alice", age: 30, city: "New York"}, {name: "Bob", age: 25, city: "Chicago"}]
```

See [The Basic Read API](./basic_read_api.md) and [Migrating from Ruby CSV](./migrating_from_csv.md).

---

## Example 3: Key Mapping and Column Selection

Rename headers and drop unwanted columns in one pass:

```ruby
options = {
  key_mapping: {
    first_name: :fname,
    last_name:  :lname,
    dob:        :birth_date,
    ssn:        nil,          # drop this column entirely
  },
}
data = SmarterCSV.process('people.csv', options)
# => [{fname: "Alice", lname: "Smith", birth_date: "1990-05-14"}, ...]
#  ↑ :ssn is gone; original CSV headers remapped to your domain names
```

Keep only specific columns using `headers: { only: }`:

```ruby
data = SmarterCSV.process('people.csv', headers: { only: [:name, :email] })
# => [{name: "Alice", email: "alice@example.com"}, ...]
```

See [Header Transformations](./header_transformations.md) and [Column Selection](./column_selection.md).

---

## Example 4: Encoding and Preamble Skip

Handle non-UTF-8 files and metadata rows before the header:

```ruby
# Bank statement export: Windows-1252, 3 preamble rows, then header
data = SmarterCSV.process('statement.csv',
  file_encoding: 'windows-1252',
  skip_lines:    3)

# European lab instrument export: semicolon-separated, Latin-1
data = SmarterCSV.process('results.csv',
  file_encoding: 'iso-8859-1',
  col_sep:       :auto)   # :auto detects the semicolon
```

See [Row and Column Separators](./row_col_sep.md) and [Real-World CSV Files](./real_world_csv.md).

---

## Example 5: Value Converters

Transform raw strings into typed values — dates, booleans, currency:

```ruby
require 'date'

data = SmarterCSV.process('records.csv',
  value_converters: {
    # Parse US date format
    dob:    ->(v) { v ? Date.strptime(v, '%m/%d/%Y') : nil },

    # Strip currency symbol and convert to Float
    price:  ->(v) { v&.delete('$,')&.to_f },

    # Boolean from various representations
    active: ->(v) { v&.match?(/\Atrue\z/i) },
  })

data.first[:dob]    # => #<Date: 1990-05-14>
data.first[:price]  # => 44.5
data.first[:active] # => true
```

Combining with `nil_values_matching` to clean sentinel values before conversion:

```ruby
data = SmarterCSV.process('export.csv',
  nil_values_matching: /\A(N\/A|NULL|#N\/A)\z/i,
  value_converters: {
    score: ->(v) { v&.to_f },   # v is nil for N/A rows — guard with &.
  })
```

See [Value Converters](./value_converters.md).

---

## Example 6: Header Validation

Raise early if required columns are missing, before processing any data rows:

```ruby
begin
  data = SmarterCSV.process('transactions.csv',
    required_keys: [:account_id, :amount, :currency])
rescue SmarterCSV::MissingKeys => e
  puts "CSV is missing required columns: #{e.keys.join(', ')}"
  # => "CSV is missing required columns: currency"
end
```

See [Header Validations](./header_validations.md).

---

## Example 7: Bad Row Handling

Collect parse errors without stopping the import:

```ruby
reader = SmarterCSV::Reader.new('data.csv', on_bad_row: :collect)
good_rows = reader.process

bad = reader.errors[:bad_rows]
puts "Imported #{good_rows.size} rows, #{bad.size} bad rows"
bad.each do |rec|
  puts "Line #{rec[:file_line_number]}: #{rec[:error_message]}"
  puts "  Raw: #{rec[:raw_line]}"
end
```

Cap the number of tolerated bad rows and limit field sizes to guard against malformed input:

```ruby
SmarterCSV.process('untrusted.csv',
  on_bad_row:       :skip,
  bad_row_limit:    10,
  field_size_limit: 4096)
```

See [Bad Row Quarantine](./bad_row_quarantine.md).

---

## Example 8: Writing CSV

```ruby
records = [
  { name: "Alice", age: 30, city: "New York" },
  { name: "Bob",   age: 25, city: "Chicago"  },
]

SmarterCSV.generate('output.csv') do |csv|
  records.each { |r| csv << r }
end
# output.csv:
# name,age,city
# Alice,30,New York
# Bob,25,Chicago
```

Writing with header renaming and value converters:

```ruby
require 'date'

SmarterCSV.generate('report.csv',
  map_headers:      { name: 'Full Name', dob: 'Date of Birth' },
  value_converters: { dob: ->(v) { v&.strftime('%m/%d/%Y') } },
) do |csv|
  User.find_each { |u| csv << { name: u.full_name, dob: u.dob } }
end
```

See [The Basic Write API](./basic_write_api.md).

---

## Example 9: Using `each` and `each_chunk` Enumerators

The modern API gives you full Enumerable power without loading the whole file:

```ruby
# each — one hash per row
reader = SmarterCSV::Reader.new('data.csv')
reader.each { |hash| MyModel.upsert(hash) }
puts reader.headers.inspect   # accessible after processing

# Enumerable methods
active_users = reader.select { |h| h[:status] == 'active' }
names        = reader.map    { |h| h[:name] }

# Lazy — stop early without reading the whole file
first_ten_active = reader.lazy.select { |h| h[:active] }.first(10)

# each_slice — manual batching without chunk_size
reader.each_slice(500) { |batch| MyModel.insert_all(batch) }
```

See [Batch Processing](./batch_processing.md) and [The Basic Read API](./basic_read_api.md).

---

## Example 10: Importing into a Database

```ruby
filename = '/tmp/some.csv'
options = { key_mapping: { unwanted_row: nil, old_row_name: :new_name } }

n = SmarterCSV.process(filename, options) do |array|
  MyModel.create(array.first)
end
# => returns number of rows processed
```

---

## Example 11: Batch Processing with Sidekiq

Processing in chunks reduces memory usage and enables parallel processing. The block receives the chunk as an optional second parameter:

```ruby
filename = '/tmp/input.csv'

n = SmarterCSV.process(filename, chunk_size: 100) do |chunk, chunk_index|
  puts "Queueing chunk #{chunk_index} with #{chunk.size} records..."
  Sidekiq::Client.push_bulk(
    'class' => SidekiqWorkerClass,
    'args'  => chunk,
  )
end
# => returns number of chunks
```

See [Batch Processing](./batch_processing.md).

---

## Example 12: Resumable CSV Import with Rails ActiveJob (Rails 8.1+)

Rails 8.1 introduced `ActiveJob::Continuable`, which lets a job pause and resume from exactly where it stopped — for example during a deployment or queue drain.

```ruby
# app/jobs/import_csv_job.rb
class ImportCsvJob < ApplicationJob
  include ActiveJob::Continuable

  def perform(file_path)
    step :import_rows do |step|
      SmarterCSV.process(file_path, chunk_size: 500) do |chunk, chunk_index|
        next if chunk_index < step.cursor.to_i  # skip already-processed chunks on resume

        MyModel.import!(chunk)
        step.set! chunk_index + 1
      end
    end
  end
end
```

- `step.cursor` starts as `nil` (→ `0`), so the first run processes all chunks.
- If interrupted after chunk 7, Rails persists the cursor as `8`.
- On the next run chunks 0–7 are skipped quickly via `next`; processing resumes from chunk 8.

> Requires Rails 8.1+ and a queue adapter that supports graceful shutdown (Sidekiq, Solid Queue).

---

## Example 13: Instrumentation

```ruby
SmarterCSV.process('large_import.csv',
  chunk_size: 1000,

  on_start: ->(info) {
    Rails.logger.info "Import started: #{info[:input]} (#{info[:file_size]} bytes)"
  },

  on_chunk: ->(info) {
    Rails.logger.debug "Chunk #{info[:chunk_number]}: #{info[:rows_in_chunk]} rows"
  },

  on_complete: ->(stats) {
    Rails.logger.info "Done: #{stats[:total_rows]} rows in #{stats[:duration].round(2)}s"
  },
) { |chunk| MyModel.insert_all(chunk) }
```

See [Instrumentation Hooks](./instrumentation.md).

---

## Example 14: Streaming Inputs (Non-Seekable IO)

*(1.17.0+)* SmarterCSV reads from gzipped files, HTTP responses, S3 objects, or piped STDIN — no need to materialize the file on disk first.

```ruby
require 'zlib'
Zlib::GzipReader.open('huge.csv.gz') do |io|
  SmarterCSV.process(io) { |row| MyModel.upsert(row.first) }
end
```

See [Real-World CSV Files → I/O Patterns](./real_world_csv.md#io-patterns) for gzip, S3, HTTP, STDIN, and `IO.popen` worked examples.

---

## Example 15: Resumable Import (Plain Ruby)

A non-Rails counterpart to Example 12 — track the chunk cursor in a JSON file so an interrupted import resumes where it left off.

See [Batch Processing → Resumable Import (Plain Ruby)](./batch_processing.md#example-resumable-import-plain-ruby) for the worked example.

---

## Example 16: CSV Files with Comment Lines

Strip lines matching a pattern (e.g. `#`-prefixed comments in DB dumps and log exports) using `comment_regexp`:

```ruby
SmarterCSV.process('data.csv', comment_regexp: /\A#/)
```

See [Header Transformations → CSV Files with Comment Lines](./header_transformations.md#csv-files-with-comment-lines) for the worked example.

---

## Example 17: Tab-Separated Values (TSV)

```ruby
SmarterCSV.process('data.tsv')                  # auto-detected
SmarterCSV.process('data.tsv', col_sep: "\t")   # explicit
```

See [Row and Column Separators → Tab-Separated Values (TSV)](./row_col_sep.md#tab-separated-values-tsv) for details.

---

## Example 18: Multi-Line Fields

Newlines inside `"..."` are preserved as part of the field — common in addresses, CRM notes, and free-text comments. No configuration needed.

See [Real-World CSV Files → Multi-Line Quoted Fields](./real_world_csv.md#multi-line-quoted-fields) for the worked example.

--------------------
PREVIOUS: [Instrumentation Hooks](./instrumentation.md) | NEXT: [Real-World CSV Files](./real_world_csv.md) | UP: [README](../README.md)
