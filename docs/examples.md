
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
  * [Bad Row Quarantine](./bad_row_quarantine.md)
  * [Warnings](./warnings.md)
  * [Instrumentation Hooks](./instrumentation.md)
  * [**Examples**](./examples.md)
  * [Real-World CSV Files](./real_world_csv.md)
  * [SmarterCSV over the Years](./history.md)
  * [Release Notes](./releases/1.18.0/changes.md)

--------------

# Examples

**Rescue from `SmarterCSV::Error` (recommended):** SmarterCSV auto-detects row and column separators. In rare cases detection fails and raises an exception (e.g. `NoColSepDetected`). Rescuing from `SmarterCSV::Error` ensures your application handles unexpected CSV formats gracefully.

---

### Reading & Parsing

- [CSV → Array of Hashes](#csv--array-of-hashes)
- [Parsing a CSV String](#parsing-a-csv-string)
- [Using `each` and `each_chunk` Enumerators](#using-each-and-each_chunk-enumerators)

### Headers & Columns

- [Key Mapping and Column Selection](#key-mapping-and-column-selection)
- [Header Validation](#header-validation)
- [Tab-Separated Values (TSV)](#tab-separated-values-tsv)

### Data Transformations

- [Value Converters](#value-converters)
- [Filtering and Transforming a CSV File](#filtering-and-transforming-a-csv-file)

### Real-World CSV Quirks

- [Encoding and Preamble Skip](#encoding-and-preamble-skip)
- [CSV Files with Comment Lines](#csv-files-with-comment-lines)
- [Multi-Line Fields](#multi-line-fields)

### Error Handling & Observability

- [Bad Row Handling](#bad-row-handling)
- [Instrumentation](#instrumentation)

### Streaming

- [Gzipped CSV files](#gzipped-csv-files)
- [Streaming a CSV over HTTP](#streaming-a-csv-over-http)
- [Streaming a CSV from S3](#streaming-a-csv-from-s3)
- [Streaming CSV via STDIN](#streaming-csv-via-stdin)
- [Streaming CSV via `IO.popen`](#streaming-csv-via-iopopen)

### Writing

- [Writing CSV](#writing-csv)
- [Generate from ActiveRecord](#generate-from-activerecord)
- [Streaming download via Rails response](#streaming-download-via-rails-response)

### Batches & Chunks

- [Importing into a Database](#importing-into-a-database)
- [Batch Processing with Sidekiq](#batch-processing-with-sidekiq)
- [Resumable CSV Import with Rails ActiveJob](#resumable-csv-import-with-rails-activejob-rails-81)
- [Resumable Import (Plain Ruby)](#resumable-import-plain-ruby)

### Parallel Processing

*Runnable standalone scripts in [`examples/parallel/`](../examples/parallel/). See also [Parallel Slicing](./parallel_slicing.md) for the API reference.*

**Canonical patterns:**
- [`serial_loop`](../examples/parallel/serial_loop/) — In-process serial loop; the simplest deployment
- [`parallel_gem`](../examples/parallel/parallel_gem/) — `Parallel.map` forked workers (POSIX)
- [`sidekiq`](../examples/parallel/sidekiq/) — Sidekiq worker pattern with `deep_symbolize_keys`
- [`chunks_only`](../examples/parallel/chunks_only/) — Pre-1.18.0 baseline (`chunk_size:` only, no slicing)
- [`slices_plus_chunks`](../examples/parallel/slices_plus_chunks/) — Slicing + chunking combined (production sweet spot)

**Sidekiq production patterns:**
- [`sidekiq_aggregator`](../examples/parallel/sidekiq_aggregator/) — Fan-in: last-finishing worker triggers an `AggregateResultsJob`
- [`sidekiq_retry`](../examples/parallel/sidekiq_retry/) — Idempotent workers via `upsert_all`
- [`sidekiq_db_table`](../examples/parallel/sidekiq_db_table/) — Per-worker state via `SliceResult` AR table
- [`sidekiq_redis_counter`](../examples/parallel/sidekiq_redis_counter/) — Per-worker state via Redis hash + atomic `DECR`

**Beyond DB import:**
- [`parallel_validation`](../examples/parallel/parallel_validation/) — Workers checksum / validate per slice
- [`parallel_filtering`](../examples/parallel/parallel_filtering/) — CSV-to-CSV transforms via per-slice tempfiles
- [`map_reduce_aggregation`](../examples/parallel/map_reduce_aggregation/) — Workers compute partial aggregates; reducer combines
- [`cross_machine_s3`](../examples/parallel/cross_machine_s3/) — S3-backed; workers fetch slice byte ranges across hosts
- [`progress_reporting`](../examples/parallel/progress_reporting/) — Per-slice progress anchored on `slice[:row_offset]`
- [`bad_row_collection`](../examples/parallel/bad_row_collection/) — `on_bad_row: :collect`; aggregator combines errors
- [`manual_fork`](../examples/parallel/manual_fork/) — Bare `Process.fork` + `Process.wait`
- [`goodjob_solid_queue`](../examples/parallel/goodjob_solid_queue/) — Same worker shape, Postgres-backed queue
- [`parallel_each_tempfiles`](../examples/parallel/parallel_each_tempfiles/) — `Parallel.each` side-effect workflow

---

### Reading & Parsing

## CSV → Array of Hashes

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

## Parsing a CSV String

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

## Using `each` and `each_chunk` Enumerators

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

### Headers & Columns

## Key Mapping and Column Selection

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

## Header Validation

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

## Tab-Separated Values (TSV)

```ruby
SmarterCSV.process('data.tsv')                  # auto-detected
SmarterCSV.process('data.tsv', col_sep: "\t")   # explicit
```

See [Row and Column Separators → Tab-Separated Values (TSV)](./row_col_sep.md#tab-separated-values-tsv) for details.

---

### Data Transformations

## Value Converters

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

## Filtering and Transforming a CSV File

The Ruby CSV library has `CSV.filter` for "read CSV, mutate each row, write CSV." In SmarterCSV this is a two-line composition of `SmarterCSV.each` and `SmarterCSV.generate`:

```ruby
SmarterCSV.generate('out.csv') do |csv|
  SmarterCSV.each('in.csv') do |row|
    row[:price] = (row[:price] * 1.1).round(2)
    row.delete(:internal_notes)
    csv << row
  end
end
```

The explicit `csv << row` is the win over `CSV.filter` — emission is intentional, not a side effect of mutating the block argument.

### Pipeline (STDIN → STDOUT)

```ruby
# cat in.csv | ruby filter.rb > out.csv
SmarterCSV.generate($stdout) do |csv|
  SmarterCSV.each($stdin) { |row| csv << row }
end
```

### Skipping rows

```ruby
SmarterCSV.generate('out.csv') do |csv|
  SmarterCSV.each('in.csv') do |row|
    next if row[:status] == 'archived'   # just skip — no emit
    csv << row
  end
end
```

### Compressed in, compressed out

```ruby
require 'zlib'
Zlib::GzipWriter.open('out.csv.gz') do |gz_out|
  SmarterCSV.generate(gz_out) do |csv|
    Zlib::GzipReader.open('in.csv.gz') do |gz_in|
      SmarterCSV.each(gz_in) { |row| csv << row }
    end
  end
end
```

Both endpoints are non-seekable streams — a pattern `CSV.filter` cannot handle, since it requires seekable input/output.

### Header renaming on the way through

```ruby
SmarterCSV.generate('out.csv', headers: [:given_name, :family_name, :email]) do |csv|
  SmarterCSV.each('in.csv',
    key_mapping: { first_name: :given_name, last_name: :family_name }
  ) { |row| csv << row }
end
```

Use `key_mapping:` on the read side to rename columns and `headers:` on the write side to enforce output column order.

---

### Real-World CSV Quirks

## Encoding and Preamble Skip

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

## CSV Files with Comment Lines

Strip lines matching a pattern (e.g. `#`-prefixed comments in DB dumps and log exports) using `comment_regexp`:

```ruby
SmarterCSV.process('data.csv', comment_regexp: /\A#/)
```

See [Header Transformations → CSV Files with Comment Lines](./header_transformations.md#csv-files-with-comment-lines) for the worked example.

---

## Multi-Line Fields

Newlines inside `"..."` are preserved as part of the field — common in addresses, CRM notes, and free-text comments. No configuration needed.

See [Real-World CSV Files → Multi-Line Quoted Fields](./real_world_csv.md#multi-line-quoted-fields) for the worked example.

---

### Error Handling & Observability

## Bad Row Handling

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

## Instrumentation

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

### Streaming

## Gzipped CSV files

*(1.17.0+)* Read a `.csv.gz` file without decompressing to disk first. Internal buffering lets auto-detection (`row_sep`, `col_sep`) work even though `Zlib::GzipReader` is non-seekable.

```ruby
require 'zlib'

Zlib::GzipReader.open('huge.csv.gz') do |io|
  SmarterCSV.process(io) { |row| MyModel.upsert(row.first) }
end
```

See [Real-World CSV Files → I/O Patterns](./real_world_csv.md#io-patterns) for more.

---

## Streaming a CSV over HTTP

*(1.17.0+)* Fetch and parse a remote CSV without staging it to disk. The simplest pattern uses `open-uri`:

```ruby
require 'open-uri'

URI.open('https://example.com/data/users.csv') do |io|
  SmarterCSV.process(io) { |row| User.upsert(row.first) }
end
```

For more control (custom headers, auth, large payloads), use `Net::HTTP` with a block — see [Real-World CSV Files → I/O Patterns](./real_world_csv.md#io-patterns).

---

## Streaming a CSV from S3

*(1.17.0+)* Use the `aws-sdk-s3` gem and hand `resp.body` (an IO-like object) directly to SmarterCSV — no local download step:

```ruby
require 'aws-sdk-s3'

client = Aws::S3::Client.new
resp   = client.get_object(bucket: 'my-bucket', key: 'exports/users.csv')

SmarterCSV.process(resp.body) { |row| User.upsert(row.first) }
```

For huge objects, use `response_target:` to stream to a tempfile first, then process; see [Real-World CSV Files → I/O Patterns](./real_world_csv.md#io-patterns).

---

## Streaming CSV via STDIN

*(1.17.0+)* For CLI tools and shell pipelines — pass `$stdin` directly:

```ruby
# my_processor.rb
SmarterCSV.process($stdin) { |row| User.upsert(row.first) }
```

```
$ cat data.csv | ruby my_processor.rb
$ curl -s https://example.com/data.csv | ruby my_processor.rb
$ zcat archive.csv.gz | ruby my_processor.rb
```

Auto-detection still works against piped STDIN because of internal buffering — the pipe never needs to support seek/rewind.

---

## Streaming CSV via `IO.popen`

*(1.17.0+)* Shell out to a command and parse its stdout as the CSV source — useful for chained tools (decompression, format conversion, remote fetch):

```ruby
# Pipe through zcat for a remote gzipped CSV
IO.popen('zcat huge.csv.gz') do |io|
  SmarterCSV.process(io) { |row| User.upsert(row.first) }
end

# Or chain curl + zcat for a remote gzipped CSV without staging
IO.popen('curl -s https://example.com/data.csv.gz | zcat') do |io|
  SmarterCSV.process(io) { |row| User.upsert(row.first) }
end
```

The subshell handles the decompression / fetch / format conversion; SmarterCSV just reads from the pipe.

---

### Writing

## Writing CSV

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

## Generate from ActiveRecord

Pair `SmarterCSV.generate` with `User.find_each` to export large tables to CSV without loading the whole table into memory. `find_each` batches DB reads; `generate` streams CSV writes:

```ruby
SmarterCSV.generate('users_export.csv') do |csv|
  User.find_each(batch_size: 1000) do |user|
    csv << {
      id:         user.id,
      name:       user.full_name,
      email:      user.email,
      created_at: user.created_at.strftime('%Y-%m-%d'),
    }
  end
end
```

With header renaming and value converters applied during write:

```ruby
require 'date'

SmarterCSV.generate('users_export.csv',
  map_headers:      { id: 'User ID', name: 'Full Name', created_at: 'Joined' },
  value_converters: { created_at: ->(v) { v&.strftime('%Y-%m-%d') } },
) do |csv|
  User.find_each(batch_size: 1000) { |u| csv << u.attributes.symbolize_keys }
end
```

Memory stays bounded by the AR batch size, regardless of total row count.

---

## Streaming download via Rails response

For Rails controllers serving CSV exports — stream the CSV directly to the user's browser without buffering the whole file in memory. Use `ActionController::Live` with `response.stream`:

```ruby
class ExportsController < ApplicationController
  include ActionController::Live

  def users
    response.headers['Content-Type']        = 'text/csv'
    response.headers['Content-Disposition'] = 'attachment; filename="users.csv"'

    SmarterCSV.generate(response.stream) do |csv|
      User.find_each(batch_size: 500) do |user|
        csv << user.attributes.symbolize_keys
      end
    end
  ensure
    response.stream.close
  end
end
```

Each batch flushes to the client as it's written — the user sees the download start immediately, and memory usage stays flat regardless of how many rows are being exported.

For smaller responses that fit in memory, `send_data` with the no-destination form of `SmarterCSV.generate` is simpler:

```ruby
class ExportsController < ApplicationController
  def users
    csv = SmarterCSV.generate do |out|
      User.find_each { |u| out << u.attributes.symbolize_keys }
    end
    send_data csv, type: 'text/csv', filename: 'users.csv'
  end
end
```

---

### Batches & Chunks

## Importing into a Database

```ruby
filename = '/tmp/some.csv'
options = { key_mapping: { unwanted_row: nil, old_row_name: :new_name } }

n = SmarterCSV.process(filename, options) do |array|
  MyModel.create(array.first)
end
# => returns number of rows processed
```

---

## Batch Processing with Sidekiq

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

## Resumable CSV Import with Rails ActiveJob (Rails 8.1+)

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

## Resumable Import (Plain Ruby)

A non-Rails counterpart to the [Rails ActiveJob example above](#resumable-csv-import-with-rails-activejob-rails-81) — track the chunk cursor in a JSON file so an interrupted import resumes where it left off.

See [Batch Processing → Resumable Import (Plain Ruby)](./batch_processing.md#example-resumable-import-plain-ruby) for the worked example.

---

### Parallel Processing

*(1.18.0+)* Slice-mode parallel CSV processing has its own examples directory: [`examples/parallel/`](../examples/parallel/) — 18 standalone runnable scripts covering serial loops, fork-based parallelism, Sidekiq deployments, aggregator jobs, validation, map-reduce, S3-backed sources, and more. See the **Parallel Processing** section in the table of contents above for the per-example links, and [Parallel Slicing](./parallel_slicing.md) for the API reference.

--------------------
PREVIOUS: [Instrumentation Hooks](./instrumentation.md) | NEXT: [Real-World CSV Files](./real_world_csv.md) | UP: [README](../README.md)
