
### Contents

  * [Introduction](./_introduction.md)
  * [**Migrating from Ruby CSV**](./migrating_from_csv.md)
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
  * [Instrumentation Hooks](./instrumentation.md)
  * [Examples](./examples.md)
  * [Real-World CSV Files](./real_world_csv.md)
  * [SmarterCSV over the Years](./history.md)
  * [Release Notes](./releases/1.16.0/changes.md)

--------------

# Migrating from Ruby CSV

Already using Ruby's built-in `CSV` library? There are three good reasons to switch — and switching is typically a one- or two-line change.

**Inconvenient.** `CSV.read` returns arrays of arrays, so your code must manually handle column indexing, header normalization, type conversion, and whitespace stripping. SmarterCSV returns Rails-ready hashes with symbol keys, numeric conversion, and whitespace stripping out of the box — no boilerplate needed.

**Hidden failure modes.** `CSV.read` has nine ways to silently corrupt or lose data — no exception, no warning, no log line. See [**Ruby CSV Pitfalls**](./ruby_csv_pitfalls.md) for reproducible examples and the SmarterCSV fix for each.

**Slow.** On top of everything else, it is up to 129× slower than SmarterCSV for equivalent end-to-end work — see the [Performance](#performance) section below.

> **Medium article:** *"Switch from Ruby CSV to SmarterCSV in 5 Minutes"* — *(coming soon)*

---

## Performance

| Comparison | Range |
|---|---|
| SmarterCSV vs `CSV.read` †  | **1.7×–8.6× faster** |
| SmarterCSV vs `CSV.table` ‡ | **7×–129× faster** |

_Benchmarks: 19 CSV files (20k–80k rows), Ruby 3.4.7, Apple M1._

_† `CSV.read` returns raw arrays of arrays — hash construction, key normalization, and type conversion still need to happen, understating the real cost difference._

_‡ `CSV.table` is the closest Ruby equivalent to SmarterCSV — both return symbol-keyed hashes._

---

## The one-line switch

Real-world CSV files are messy — whitespace-padded headers, extra columns without headers, trailing
commas. Consider this file:

```
$ cat data.csv
   First Name  , Last Name , Age
Alice , Smith,  30, VIP, Gold ,
Bob, Jones,  25
```

**With Ruby CSV:**
```ruby
rows = CSV.read('data.csv', headers: true).map(&:to_h)
rows.first
# => { "   First Name  " => "Alice ", " Last Name " => " Smith", " Age" => "  30", nil => "" }
#    "VIP" and "Gold" silently lost — both compete for the nil key, last one wins
```

Whitespace-polluted keys, `Age` as a string, and extra columns competing for the same `nil` key —
the last one wins and the rest are silently discarded.

**With SmarterCSV:**
```ruby
rows = SmarterCSV.process('data.csv')
rows.first
# => { first_name: "Alice", last_name: "Smith", age: 30, column_1: "VIP", column_2: "Gold" }
```

Clean symbol keys, whitespace stripped, `age` converted to `Integer`, extra columns named — no data loss.

No `.map(&:to_h)`, no `header_converters:`, no manual post-processing.

---

## Sample file used in remaining examples

The sections below use a simpler file to keep the focus on the specific behavior being illustrated:

```
$ cat sample.csv
name,age,city
Alice,30,New York
Bob,25,
Charlie,35,Chicago
```

Bob's `city` field is intentionally empty to illustrate empty-value handling.

---

## Parsing a CSV string

**With Ruby CSV:**
```ruby
csv_string = "name,age,city\nAlice,30,New York\nBob,25,\nCharlie,35,Chicago\n"

rows = CSV.parse(csv_string, headers: true, header_converters: :symbol).map(&:to_h)
# => [
#      { name: "Alice",   age: "30", city: "New York" },
#      { name: "Bob",     age: "25", city: nil },
#      { name: "Charlie", age: "35", city: "Chicago" }
#    ]
```

**With SmarterCSV:**
```ruby
rows = SmarterCSV.parse(csv_string)
# => [
#      { name: "Alice",   age: 30, city: "New York" },
#      { name: "Bob",     age: 25 },
#      { name: "Charlie", age: 35, city: "Chicago" }
#    ]
```

`SmarterCSV.parse` is a convenience wrapper added in 1.16.0. Under the hood it wraps the
string in a `StringIO` — but you don't need to think about that.

---

## Row-by-row iteration

**With Ruby CSV:**
```ruby
CSV.foreach('sample.csv', headers: true, header_converters: :symbol) do |row|
  MyModel.create(row.to_h)   # row is a CSV::Row — needs .to_h
end
```

**With SmarterCSV:**
```ruby
SmarterCSV.each('sample.csv') do |row|
  MyModel.create(row)        # row is already a plain Hash — no .to_h needed
end
```

`SmarterCSV.each` returns an `Enumerator` when called without a block, so the full
`Enumerable` API is available:

```ruby
names   = SmarterCSV.each('sample.csv').map    { |row| row[:name] }
# => ["Alice", "Bob", "Charlie"]

us_rows = SmarterCSV.each('sample.csv').select { |row| row[:city] == 'New York' }
# => [{ name: "Alice", age: 30, city: "New York" }]

first2  = SmarterCSV.each('sample.csv').lazy.first(2)
# => [{ name: "Alice", age: 30, city: "New York" }, { name: "Bob", age: 25 }]
```

---

## Key behavior differences

### 1. String keys → Symbol keys

`CSV.read` returns string keys by default. SmarterCSV returns symbol keys, which are more
efficient (interned in memory) and idiomatic for Rails and ActiveRecord.

**With Ruby CSV:**
```ruby
rows = CSV.read('sample.csv', headers: true).map(&:to_h)
rows.first['name']   # => "Alice"
rows.first['age']    # => "30"
```

**With SmarterCSV:**
```ruby
rows = SmarterCSV.process('sample.csv')
rows.first[:name]    # => "Alice"
rows.first[:age]     # => 30

# To match CSV.read string-key behaviour:
rows = SmarterCSV.process('sample.csv', strings_as_keys: true)
rows.first['name']   # => "Alice"
```

### 2. Numeric conversion is automatic

`CSV.read` returns everything as strings. SmarterCSV converts numeric strings to `Integer`
or `Float` automatically — no `converters: :numeric` needed.

Watch out for columns where leading zeros matter — ZIP codes, phone numbers, account numbers —
and exclude them:

**With Ruby CSV:**
```ruby
rows = CSV.read('sample.csv', headers: true).map(&:to_h)
rows.first['age']        # => "30"  (String)
rows.first['age'].class  # => String
```

**With SmarterCSV:**
```ruby
rows = SmarterCSV.process('sample.csv')
rows.first[:age]         # => 30  (Integer)
rows.first[:age].class   # => Integer

# Exclude columns where leading zeros matter:
rows = SmarterCSV.process('sample.csv',
  convert_values_to_numeric: { except: [:zip_code, :phone, :account_number] })
```

### 3. Empty values are removed by default

SmarterCSV drops key/value pairs where the value is `nil` or blank
(`remove_empty_values: true` is the default). Ruby CSV keeps them as `nil`.

**With Ruby CSV:**
```ruby
rows = CSV.read('sample.csv', headers: true, header_converters: :symbol).map(&:to_h)
rows[1]   # => { name: "Bob", age: "25", city: nil }
```

**With SmarterCSV:**
```ruby
rows = SmarterCSV.process('sample.csv')
rows[1]   # => { name: "Bob", age: 25 }  ← empty city removed

# To keep nil values and match Ruby CSV behaviour:
rows = SmarterCSV.process('sample.csv', remove_empty_values: false)
rows[1]   # => { name: "Bob", age: 25, city: nil }
```

### 4. Plain Hash, not CSV::Row

Ruby CSV returns `CSV::Row` objects. SmarterCSV returns plain Ruby `Hash` objects.

`CSV::Row` wraps a hash with extra methods (`.headers`, `.fields`, `.to_h`, `.to_a`).
With SmarterCSV you work directly with the hash — no wrapper, no `.to_h` needed.

**With Ruby CSV:**
```ruby
row = CSV.read('sample.csv', headers: true).first
row.class       # => CSV::Row
row['name']     # => "Alice"
row['age']      # => "30"  (String)
row.to_h        # => { "name" => "Alice", "age" => "30", "city" => "New York" }
```

**With SmarterCSV:**
```ruby
row = SmarterCSV.process('sample.csv').first
row.class       # => Hash
row[:name]      # => "Alice"
row[:age]       # => 30  (Integer)
row             # => { name: "Alice", age: 30, city: "New York" }
```

---

## Renaming headers to match your schema

CSV column names rarely match your ActiveRecord attribute names. Use `key_mapping:` to rename
them in one step — the mapping uses the normalized (downcased, underscored) header name as input:

**With SmarterCSV:**
```ruby
# CSV headers: "First Name", "Last Name", "E-Mail", "Date of Birth"
# After normalization: :first_name, :last_name, :e_mail, :date_of_birth

rows = SmarterCSV.process('contacts.csv',
  key_mapping: {
    first_name:    :given_name,
    last_name:     :family_name,
    e_mail:        :email,
    date_of_birth: :dob,
  })
# => [{ given_name: "Alice", family_name: "Smith", email: "alice@example.com", dob: "1990-05-14" }, ...]
```

Map a key to `nil` to drop that column entirely:

```ruby
key_mapping: { internal_id: nil, created_at: nil }   # these columns won't appear in results
```

---

## Select only the columns you need

Wide CSV files often have dozens of columns your application doesn't need. Use `headers: { only: }`
to declare upfront which columns to keep — SmarterCSV skips everything else at the parser level,
so unneeded fields are never allocated:

**With SmarterCSV:**
```ruby
# CSV has 50 columns — you only need 3
rows = SmarterCSV.process('contacts.csv',
  headers: { only: [:email, :first_name, :last_name] })
# => [{ email: "alice@example.com", first_name: "Alice", last_name: "Smith" }, ...]

# Or exclude a known noisy column while keeping everything else:
rows = SmarterCSV.process('export.csv', headers: { except: [:internal_notes] })
```

---

## Date / DateTime conversion

Ruby CSV has built-in `:date` and `:date_time` converters. SmarterCSV intentionally omits
them because date formats are locale-dependent (`12/03/2020` means December 3rd in the US
but March 12th in Europe). Use a `value_converter` instead:

**With Ruby CSV:**
```ruby
rows = CSV.read('data.csv', headers: true, converters: :date)
rows.first['birth_date']   # => #<Date: 1990-05-15>  (assumes ISO 8601 format only)
```

**With SmarterCSV:**
```ruby
require 'date'

rows = SmarterCSV.process('data.csv',
  value_converters: {
    birth_date: ->(v) { v ? Date.strptime(v, '%Y-%m-%d') : nil },   # ISO 8601
    # birth_date: ->(v) { v ? Date.strptime(v, '%m/%d/%Y') : nil }, # US format
    # birth_date: ->(v) { v ? Date.strptime(v, '%d.%m.%Y') : nil }, # EU format
  })
rows.first[:birth_date]   # => #<Date: 1990-05-15>
```

See [Value Converters](./value_converters.md) for full details.

---

## Custom value converters

SmarterCSV lets you apply any transformation per column — prices, booleans, custom types:

**With SmarterCSV:**
```ruby
rows = SmarterCSV.process('records.csv',
  value_converters: {
    birth_date: ->(v) { v ? Date.strptime(v, '%m/%d/%Y') : nil },
    price:      ->(v) { v&.delete('$,')&.to_f },
    active:     ->(v) { v&.match?(/\Atrue\z/i) },
  })
```

See [Value Converters](./value_converters.md) for full details.

---

## Sentinel values (NULL, NaN, #VALUE!)

Ruby CSV leaves these as strings. SmarterCSV lets you nil-ify them (and optionally remove
the key) in a single option:

**With SmarterCSV:**
```ruby
# Remove keys where value matches (remove_empty_values: true is the default)
rows = SmarterCSV.process('data.csv', nil_values_matching: /\A(NULL|N\/A|NaN|#VALUE!)\z/i)
# fields matching the pattern are removed entirely

# Keep the key but set the value to nil:
rows = SmarterCSV.process('data.csv',
  nil_values_matching: /\ANULL\z/,
  remove_empty_values: false,
)
# => [{ name: "Alice", score: nil, ... }]
```

---

## Malformed / bad rows

**With Ruby CSV:**
```ruby
# Silent ignore — errors are swallowed
rows = CSV.read('data.csv', liberal_parsing: true)
```

**With SmarterCSV:**
```ruby
# Collect bad rows so you can inspect, log, or quarantine them
reader = SmarterCSV::Reader.new('data.csv', on_bad_row: :collect)
good_rows = reader.process
bad_rows  = reader.errors[:bad_rows]

puts "#{good_rows.size} imported, #{bad_rows.size} bad rows"
bad_rows.each { |r| puts "Line #{r[:file_line_number]}: #{r[:error_message]}" }
```

See [Bad Row Quarantine](./bad_row_quarantine.md) for full details.

---

## Batch processing for large files

**With SmarterCSV:**
```ruby
SmarterCSV.process('big.csv', chunk_size: 500) do |chunk|
  MyModel.insert_all(chunk)   # bulk insert 500 rows at a time
end
```

---

## Writing CSV

**With Ruby CSV:**
```ruby
CSV.open('out.csv', 'w', write_headers: true, headers: ['name', 'age']) do |csv|
  csv << ['Alice', 30]
  csv << ['Bob',   25]
end
```

**With SmarterCSV:**
```ruby
# Takes hashes, discovers headers automatically
SmarterCSV.generate('out.csv') do |csv|
  csv << { name: 'Alice', age: 30 }
  csv << { name: 'Bob',   age: 25 }
end
```

SmarterCSV's writer also accepts any IO object (StringIO, open file handle) for streaming:

```ruby
io = StringIO.new
SmarterCSV.generate(io) { |csv| records.each { |r| csv << r } }
send_data io.string, type: 'text/csv'
```

---

## Advanced patterns

### Rails file upload

Accepting a CSV upload in a Rails controller — pass the tempfile path directly:

```ruby
def create
  file = params[:file]   # ActionDispatch::Http::UploadedFile

  SmarterCSV.process(file.path, chunk_size: 500) do |chunk|
    MyModel.insert_all(chunk)
  end

  redirect_to root_path, notice: "Import complete"
end
```

### Parallel processing with Sidekiq

```ruby
SmarterCSV.process('users.csv', chunk_size: 100) do |chunk, chunk_index|
  puts "Queueing chunk #{chunk_index} (#{chunk.size} records)..."
  Sidekiq::Client.push_bulk(
    'class' => UserImportWorker,
    'args'  => chunk,
  )
end
```

### Streaming directly from S3

SmarterCSV accepts any IO-like object — stream a CSV directly from S3 without writing a temp file:

```ruby
require 'aws-sdk-s3'

s3  = Aws::S3::Client.new(region: 'us-east-1')
obj = s3.get_object(bucket: 'my-bucket', key: 'imports/contacts.csv')

SmarterCSV::Reader.new(obj.body, chunk_size: 500).each_chunk do |chunk, _index|
  MyModel.insert_all(chunk)
end
```

### Production instrumentation

```ruby
SmarterCSV.process('large_import.csv',
  chunk_size: 1_000,
  on_start:    ->(info)  { Rails.logger.info  "Import started: #{info[:input]} (#{info[:file_size]} bytes)" },
  on_chunk:    ->(info)  { Rails.logger.debug "Chunk #{info[:chunk_number]}: #{info[:rows_in_chunk]} rows (#{info[:total_rows_so_far]} total)" },
  on_complete: ->(stats) {
    Rails.logger.info "Done: #{stats[:total_rows]} rows in #{stats[:duration].round(2)}s, #{stats[:bad_rows]} bad rows"
    StatsD.histogram('csv.import.duration', stats[:duration])
  },
) { |chunk| MyModel.insert_all(chunk) }
```

See [Instrumentation Hooks](./instrumentation.md) for full details.

### Resumable imports with Rails ActiveJob

Rails 8.1 introduced `ActiveJob::Continuable` — jobs that pause on deployment and resume exactly
where they stopped. SmarterCSV's `chunk_index` maps directly onto the job cursor:

```ruby
class ImportCsvJob < ApplicationJob
  include ActiveJob::Continuable

  def perform(file_path)
    step :import_rows do |step|
      SmarterCSV.process(file_path, chunk_size: 500) do |chunk, chunk_index|
        next if chunk_index < step.cursor.to_i   # skip already-processed chunks on resume

        MyModel.insert_all(chunk)
        step.set! chunk_index + 1
      end
    end
  end
end
```

### Bulk upsert — insert or update

```ruby
SmarterCSV.process('contacts.csv',
  chunk_size: 500,
  key_mapping: { e_mail: :email },
) do |chunk|
  Contact.upsert_all(chunk, unique_by: :email)
end
```

---

## Quick reference

| Ruby CSV | SmarterCSV equivalent | Notes |
|---|---|---|
| `CSV.read(f, headers: true).map(&:to_h)` | `SmarterCSV.process(f)` | Symbol keys, numeric conversion, whitespace stripped. |
| `CSV.read(f, headers: true, header_converters: :symbol).map(&:to_h)` | `SmarterCSV.process(f)` | Drop-in. |
| `CSV.table(f).map(&:to_h)` | `SmarterCSV.process(f)` | Drop-in. |
| `CSV.parse(str, headers: true, header_converters: :symbol)` | `SmarterCSV.parse(str)` | Direct string parsing. |
| `CSV.foreach(f, headers: true) { \|r\| }` | `SmarterCSV.each(f) { \|r\| }` | Row is already a plain Hash. |
| `converters: :numeric` | default | Automatic in SmarterCSV. |
| `converters: :date` | `value_converters: {col: ->(v) { ... } }` | Use explicit format strings — date formats are locale-dependent. |
| `liberal_parsing: true` | `on_bad_row: :collect` | Explicit quarantine gives you visibility. |
| `skip_blanks: true` | `remove_empty_hashes: true` | Default in SmarterCSV. |
| `row.to_h` | `row` | Already a plain Hash — no conversion needed. |
| `row.headers` | `reader.headers` | Available on the `Reader` instance. |

---
PREVIOUS: [Introduction](./_introduction.md) | NEXT: [Ruby CSV Pitfalls](./ruby_csv_pitfalls.md) | UP: [README](../README.md)

