
### Contents

  * [Introduction](./_introduction.md)
  * [**Migrating from Ruby CSV**](./migrating_from_csv.md)
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
  * [SmarterCSV over the Years](./history.md)

--------------

# Migrating from Ruby CSV

Already using Ruby's built-in `CSV` library? Switching to SmarterCSV is typically a one- or
two-line change — and you get **6× to 119× faster parsing**, plain Ruby hashes with symbol
keys, automatic type conversion, and a much richer feature set in return.

> **Medium article:** *"Switch from Ruby CSV to SmarterCSV in 5 Minutes"* — *(coming soon)*

---

## The one-line switch

```ruby
# Before — Ruby CSV
rows = CSV.table('data.csv').map(&:to_h)   # array of hashes with symbol keys

# After — SmarterCSV (drop-in, up to 119× faster)
rows = SmarterCSV.process('data.csv')      # array of hashes with symbol keys
```

That's it for the common case. Keep reading for the few behavior differences to be aware of.

---

## Parsing a CSV string

```ruby
csv_string = "name,age\nAlice,30\nBob,25\n"

# Ruby CSV
rows = CSV.parse(csv_string, headers: true, header_converters: :symbol)

# SmarterCSV — direct string parsing
rows = SmarterCSV.parse(csv_string)
# => [{name: "Alice", age: 30}, {name: "Bob", age: 25}]
```

`SmarterCSV.parse` is a convenience wrapper added in 1.16.0. Under the hood it wraps the
string in a `StringIO` — but you don't need to think about that.

---

## Row-by-row iteration

```ruby
# Ruby CSV
CSV.foreach('data.csv', headers: true, header_converters: :symbol) do |row|
  MyModel.create(row.to_h)
end

# SmarterCSV
SmarterCSV.each('data.csv') do |row|
  MyModel.create(row)          # row is already a plain Hash — no .to_h needed
end
```

`SmarterCSV.each` returns an `Enumerator` when called without a block, so the full
`Enumerable` API is available:

```ruby
names = SmarterCSV.each('data.csv').map { |row| row[:name] }
us_rows = SmarterCSV.each('data.csv').select { |row| row[:country] == 'US' }
first10 = SmarterCSV.each('data.csv').lazy.first(10)
```

---

## Key behavior differences

### 1. Symbol keys (same as `CSV.table`, different from `CSV.read`)

SmarterCSV returns symbol keys by default — the same as `CSV.table`. If you were using
`CSV.read` with string keys, add `strings_as_keys: true`:

```ruby
# Ruby CSV.read — string keys
rows = CSV.read('data.csv', headers: true)
rows.first['name']   # string key

# SmarterCSV default — symbol keys (same as CSV.table)
rows = SmarterCSV.process('data.csv')
rows.first[:name]    # symbol key

# SmarterCSV with string keys — if you need to match CSV.read behaviour
rows = SmarterCSV.process('data.csv', strings_as_keys: true)
rows.first['name']
```

### 2. Numeric conversion is automatic

SmarterCSV converts numeric strings to `Integer` or `Float` automatically (the `:numeric`
converter in Ruby CSV terms). You get integers and floats back without requesting it:

```ruby
# Ruby CSV — explicit converter needed
CSV.table('data.csv', converters: :numeric)

# SmarterCSV — automatic (convert_values_to_numeric: true is the default)
SmarterCSV.process('data.csv')
```

To disable: `convert_values_to_numeric: false`.

To limit conversion to specific columns:
```ruby
SmarterCSV.process('data.csv', convert_values_to_numeric: { only: [:age, :score] })
SmarterCSV.process('data.csv', convert_values_to_numeric: { except: [:zip_code] })
```

### 3. Empty values are removed by default

SmarterCSV drops key/value pairs where the value is `nil` or blank
(`remove_empty_values: true` is the default). Ruby CSV keeps them as `nil`.

```ruby
# CSV "Alice,,30" with header "name,city,age"

# Ruby CSV — nil values present
# => {name: "Alice", city: nil, age: 30}

# SmarterCSV default — nil removed
# => {name: "Alice", age: 30}

# SmarterCSV — keep nil values (match Ruby CSV behaviour)
SmarterCSV.process('data.csv', remove_empty_values: false)
# => {name: "Alice", city: nil, age: 30}
```

### 4. Plain Hash, not CSV::Row

Ruby CSV returns `CSV::Row` objects. SmarterCSV returns plain Ruby `Hash` objects.

`CSV::Row` wraps a hash with extra methods (`.headers`, `.fields`, `.to_h`, `.to_a`).
With SmarterCSV you work directly with the hash — no wrapper, no `.to_h` needed.

```ruby
# Ruby CSV — CSV::Row object
row = CSV.table('data.csv').first
row.class       # => CSV::Row
row.headers     # => [:name, :age]
row.to_h        # => {name: "Alice", age: 30}

# SmarterCSV — plain Hash
row = SmarterCSV.process('data.csv').first
row.class       # => Hash
row.keys        # => [:name, :age]
row             # => {name: "Alice", age: 30}
```

---

## Date / DateTime conversion

Ruby CSV has built-in `:date` and `:date_time` converters. SmarterCSV intentionally omits
them because date formats are locale-dependent (`12/03/2020` means December 3rd in the US
but March 12th in Europe). Use a `value_converter` instead:

```ruby
require 'date'

# ISO 8601 (YYYY-MM-DD) — unambiguous
iso_date = Class.new { def self.convert(v) = v ? Date.strptime(v, '%Y-%m-%d') : nil }

SmarterCSV.process('data.csv', value_converters: { birth_date: iso_date })
```

See [Value Converters](./value_converters.md) for full details and examples for US/EU formats.

---

## Sentinel values (NULL, NaN, #VALUE!)

Ruby CSV leaves these as strings. SmarterCSV lets you nil-ify them (and optionally remove
the key) in a single option:

```ruby
# Remove rows where any value is NULL or an Excel error
SmarterCSV.process('data.csv', nil_values_matching: /\A(NULL|NaN|#VALUE!)\z/)

# Keep the key but set the value to nil (useful for distinguishing "missing" from "absent")
SmarterCSV.process('data.csv',
  nil_values_matching: /\ANULL\z/,
  remove_empty_values: false,
)
```

---

## Malformed / bad rows

Ruby CSV has `liberal_parsing: true` to silently swallow parse errors.
SmarterCSV gives you explicit control:

```ruby
# Ruby CSV — silent ignore
CSV.read('data.csv', liberal_parsing: true)

# SmarterCSV — collect bad rows so you can inspect them
reader = SmarterCSV::Reader.new('data.csv', on_bad_row: :collect)
good_rows = reader.process
bad_rows  = reader.errors[:bad_rows]   # inspect / log / quarantine
```

See [Bad Row Quarantine](./bad_row_quarantine.md) for full details.

---

## Writing CSV

```ruby
# Ruby CSV
CSV.open('out.csv', 'w', write_headers: true, headers: ['name','age']) do |csv|
  csv << ['Alice', 30]
end

# SmarterCSV — takes hashes, discovers headers automatically
SmarterCSV.generate('out.csv') do |csv|
  csv << {name: 'Alice', age: 30}
  csv << {name: 'Bob',   age: 25}
end
```

SmarterCSV's writer also accepts any IO object (StringIO, open file handle) for streaming:

```ruby
io = StringIO.new
SmarterCSV.generate(io) { |csv| records.each { |r| csv << r } }
send_data io.string, type: 'text/csv'
```

---

## Quick reference

| Ruby CSV | SmarterCSV equivalent | Notes |
|---|---|---|
| `CSV.table(f)` | `SmarterCSV.process(f)` | Drop-in. Symbol keys, numeric conversion. |
| `CSV.read(f, headers: true)` | `SmarterCSV.process(f, strings_as_keys: true)` | Add `strings_as_keys:` for string keys. |
| `CSV.parse(str, headers: true, header_converters: :symbol)` | `SmarterCSV.parse(str)` | Direct string parsing. |
| `CSV.foreach(f, headers: true) { \|r\| }` | `SmarterCSV.each(f) { \|r\| }` | Row is already a plain Hash. |
| `converters: :numeric` | default | Automatic in SmarterCSV. |
| `converters: :date` | `value_converters: {col: DateConverter}` | See [Value Converters](./value_converters.md). |
| `liberal_parsing: true` | `on_bad_row: :collect` | Explicit quarantine is better. |
| `skip_blanks: true` | `remove_empty_hashes: true` | Default in SmarterCSV. |
| `row.to_h` | `row` | Already a plain Hash — no conversion needed. |
| `row.headers` | `reader.headers` | Available on the `Reader` instance. |

---

## Performance

For a fair comparison, `CSV.table` is the closest Ruby equivalent (both return symbol-keyed hashes):

| Comparison | Range |
|---|---|
| SmarterCSV vs `CSV.table` | **6× to 119× faster** |
| SmarterCSV vs `CSV.read`  | **1.8× to 7.5× faster** |

_Benchmarks: 16 CSV files (43k–80k rows), Ruby 3.4.7, Apple M1._

---

PREVIOUS: [Introduction](./_introduction.md) | NEXT: [Parsing Strategy](./parsing_strategy.md)
