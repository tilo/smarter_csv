
### Contents

  * [Introduction](./_introduction.md)
  * [Migrating from Ruby CSV](./migrating_from_csv.md)
  * [**Ruby CSV Pitfalls**](./ruby_csv_pitfalls.md)
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

---

# Ruby CSV Pitfalls: Silent Data Corruption and Loss

Ruby's built-in `CSV` library is convenient, but it has failure modes that produce **no exception, no warning, and no indication that anything went wrong**. Your import runs, your tests pass, and your data is quietly wrong.

This page documents nine reproducible ways `CSV.read` (and `CSV.table`) can silently corrupt or lose data, with examples you can run yourself, and how SmarterCSV handles each case.

> **Note on `CSV.table`:** It is a convenience wrapper for `CSV.read` with `headers: true`, `header_converters: :symbol`, and `converters: :numeric`. The `:symbol` header converter includes `.strip`, which is why issue #5 is the only one it mitigates. All other issues are identical to `CSV.read`.

---

## At a Glance

| # | Issue | Failure Mode | `CSV.table` same? | SmarterCSV fix |
|---|-------|-------------|:-----------------:|----------------|
| 1 | Extra columns silently dropped | Values beyond header count compete for the `nil` key — all but the last are discarded | Yes | `missing_headers: :auto` (default) auto-generates `:column_N` keys |
| 2 | Duplicate headers — last wins | `.to_h` keeps only the last value for a repeated header; earlier values silently lost | Yes | `duplicate_header_suffix:` (default `""`) → `:score`, `:score2`, `:score3` |
| 3 | Empty headers — `""` key collision | Blank header cells become `""` keys; multiple blanks collide and overwrite each other | Yes | `missing_header_prefix:` (default `"column_"`) → `:column_2`, `:column_5` |
| 4 | BOM corrupts first header | `"\xEF\xBB\xBFname"` ≠ `"name"` — first column becomes unreachable by its key | Yes | Automatic BOM stripping — always on, no option needed |
| 5 | Whitespace in headers | `" Age"` ≠ `"Age"` — lookup silently returns `nil` | **No** | `strip_whitespace: true` (default) strips headers and values |
| 6 | `liberal_parsing` garbles fields | Unmatched quotes produce wrong field boundaries — corrupted data returned as valid | Yes | `on_bad_row: :raise` (default); opt-in `:skip` / `:collect` for quarantine |
| 7 | `nil` vs `""` for empty fields | Unquoted empty → `nil`, quoted empty → `""` — inconsistent empty checks | Yes | `remove_empty_values: true` (default) removes both; `false` normalizes both to `nil` |
| 8 | Missing closing quote eats the rest of the file | One unclosed `"` swallows all subsequent rows into one field value | Yes | `field_size_limit: N` raises immediately; `quote_boundary: :standard` (default) reduces exposure |
| 9 | No encoding auto-detection | Non-UTF-8 files either crash or silently produce mojibake | Yes | `file_encoding:`, `force_utf8: true`, `invalid_byte_sequence:` |

---

## 1. Extra Columns Without Headers — Values Silently Discarded

When a row has more fields than there are headers, `CSV.read` keys every extra field under `nil`. If there are multiple extra fields, they all compete for the same `nil` key — **only the last one survives**.

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
# => {"   First Name  " => "Alice ", " Last Name " => " Smith", " Age" => "  30", nil => ""}
#                                                                                   ^^^ "VIP" and "Gold" silently lost
```

Alice's row has 6 fields but only 3 headers. The extra fields `"VIP"`, `"Gold"`, and `""` (trailing comma) all land on `nil` — each overwriting the last. No error, no warning.

This is common in real-world exports: tools frequently append audit columns, status flags, or trailing commas that don't correspond to headers.

**With SmarterCSV:**

```ruby
rows = SmarterCSV.process('data.csv')
rows.first
# => {first_name: "Alice", last_name: "Smith", age: 30, column_1: "VIP", column_2: "Gold"}
```

`missing_headers: :auto` (default) auto-generates distinct names for extra columns using `missing_header_prefix` (default: `"column_"`). The trailing empty field is dropped by `remove_empty_values: true` (default).

---

## 2. Duplicate Header Names — First Value Silently Dropped

When two columns share the same header name, `CSV::Row#to_h` keeps only the **last** value. The first is silently dropped.

**With Ruby CSV:**

```ruby
csv = "score,name,score\n95,Alice,87"
rows = CSV.parse(csv, headers: true).map(&:to_h)
rows.first
# => {"score" => "87", "name" => "Alice"}
#    ^^^ first score (95) silently lost
```

Common with reporting tool exports that repeat a column (e.g., two date columns both labeled `"Date"`).

**With SmarterCSV:**

```ruby
rows = SmarterCSV.process(StringIO.new(csv))
rows.first
# => {score: 95, name: "Alice", score2: 87}
```

`duplicate_header_suffix:` (default `""`) disambiguates by appending a counter: `:score`, `:score2`, `:score3`. Use `duplicate_header_suffix: '_'` to get `:score_2`, `:score_3`. Set to `nil` to raise `DuplicateHeaders` instead.

---

## 3. Empty Header Fields — `""` Key Collision

A CSV file with blank header cells (e.g., `name,,age`) gives those columns an empty string key. Multiple blank headers all collide on `""` — same overwrite problem as issue #1.

> This is distinct from issue #1. Issue #1 is about extra *data* fields beyond the header count, which get keyed under `nil`. Issue #3 is about blank cells *in the header row itself*, which get keyed under `""`.

**With Ruby CSV:**

```ruby
csv = "name,,,age\nAlice,foo,bar,30"
rows = CSV.parse(csv, headers: true).map(&:to_h)
rows.first
# => {"name" => "Alice", "" => "bar", "age" => "30"}
#    ^^^ "foo" silently lost — both blank headers wrote to the "" key
```

`CSV.table` converts headers to symbols — blank headers become `:"" ` — same collision, different key:

```ruby
rows = CSV.table(StringIO.new(csv)).map(&:to_h)
rows.first
# => {name: "Alice", :"" => "bar", age: 30}
#    ^^^ "foo" still silently lost
```

**With SmarterCSV:**

```ruby
rows = SmarterCSV.process(StringIO.new(csv))
rows.first
# => {name: "Alice", column_2: "foo", column_3: "bar", age: 30}
```

`missing_header_prefix:` (default `"column_"`) auto-generates names for blank headers: `:column_2`, `:column_3`, etc. No collision, no data loss.

---

## 4. BOM Corrupts the First Header

Files saved by Excel on Windows often include a UTF-8 BOM (`\xEF\xBB\xBF`) at the start. `CSV.read` does not strip it, so the BOM is silently prepended to the first header name.

**With Ruby CSV:**

```ruby
# File saved by Excel with UTF-8 BOM
rows = CSV.read('excel_export.csv', headers: true).map(&:to_h)
rows.first.keys.first   # => "\xEF\xBB\xBFname"  ← not "name"

rows.first['name']      # => nil   ← first column unreachable
```

The data is present but every lookup on the first column silently returns `nil`. The BOM is invisible in most terminals and editors — the output appears correct.

**With SmarterCSV:**

```ruby
rows = SmarterCSV.process('excel_export.csv')
rows.first[:name]       # => "Alice"  ← BOM stripped automatically
```

SmarterCSV automatically detects and strips BOMs. Always on, no option needed.

---

## 5. Whitespace in Header Names — Silent `nil` on Lookup

`CSV.read` returns headers exactly as they appear in the file, including leading and trailing whitespace. Code that accesses columns by the expected name silently gets `nil`.

**With Ruby CSV:**

```ruby
csv = " name , age \nAlice,30"
rows = CSV.parse(csv, headers: true).map(&:to_h)
rows.first
# => {" name " => "Alice", " age " => "30"}

rows.first['name']   # => nil  ← key is " name ", not "name"
rows.first['age']    # => nil
```

> `CSV.table` mitigates this: the `:symbol` header converter includes `.strip`. This is the one issue where `CSV.table` behaves better than `CSV.read`.

**With SmarterCSV:**

```ruby
rows = SmarterCSV.process(StringIO.new(csv))
rows.first
# => {name: "Alice", age: 30}
```

`strip_whitespace: true` (default) strips leading/trailing whitespace from both headers and values.

---

## 6. `liberal_parsing: true` Garbles Field Values

`CSV.read` raises `MalformedCSVError` when it encounters an unmatched quote. `liberal_parsing: true` suppresses the error and returns a row anyway — but with wrong field boundaries.

**The key danger:** without `liberal_parsing` you at least know something is wrong. With it, corrupted data is silently returned as valid.

**With Ruby CSV:**

```ruby
csv = "name,note,score\nAlice,\"unclosed quote,99\nBob,normal,87"

# Without liberal_parsing: you know something is wrong
CSV.parse(csv, headers: true)
# => CSV::MalformedCSVError: Unclosed quoted field on line 2

# With liberal_parsing: silent corruption
rows = CSV.parse(csv, headers: true, liberal_parsing: true).map(&:to_h)
rows.length   # => 1  (not 2 — Bob's row is gone)
rows[0]
# => {"name" => "Alice", "note" => "unclosed quote,99\nBob,normal,87", "score" => nil}
#    ^^^ Alice's note field swallowed the rest of the file; Bob vanished
```

The garbled row passes validations, gets inserted into the database, and surfaces as a data quality issue later.

**With SmarterCSV:**

```ruby
reader = SmarterCSV::Reader.new('data.csv', on_bad_row: :collect)
good_rows = reader.process
bad_rows  = reader.errors[:bad_rows]   # inspect, log, or reprocess
puts "#{good_rows.size} good, #{bad_rows.size} bad"
```

`on_bad_row: :raise` (default) fails fast. `:skip` discards bad rows. `:collect` quarantines them with line number and error message — bad rows are never silently mangled and returned as good data.

---

## 7. `nil` vs `""` for Empty Fields — Inconsistent Empty Checks

`CSV.read` treats unquoted empty fields and quoted empty fields differently:

- Unquoted empty (`,,`) → `nil`
- Quoted empty (`,"",`) → `""`

**With Ruby CSV:**

```ruby
csv = "name,city\nAlice,\nBob,\"\""
rows = CSV.parse(csv, headers: true).map(&:to_h)

rows[0]['city']        # => nil   (unquoted empty)
rows[1]['city']        # => ""    (quoted empty)

rows[0]['city'].nil?   # => true
rows[1]['city'].nil?   # => false  ← same semantic meaning, different Ruby type
```

Both rows have no city, but your code sees two different things. Any check using `.nil?`, `.blank?`, `.present?`, or `if row['city']` will behave differently depending on how the upstream exporter quoted the empty field.

**With SmarterCSV:**

```ruby
rows = SmarterCSV.process(StringIO.new(csv))
# remove_empty_values: true (default) — both are dropped from the hash
rows[0].key?(:city)   # => false
rows[1].key?(:city)   # => false

# To keep empty fields — both normalized to nil:
rows = SmarterCSV.process(StringIO.new(csv), remove_empty_values: false)
rows[0][:city]        # => nil
rows[1][:city]        # => nil
```

---

## 8. Missing Closing Quote Consumes the Rest of the File

A single unclosed `"` causes the parser to enter quoted-field mode and treat everything that follows — newlines included — as part of one field. **All remaining rows are swallowed into a single field value.**

**With Ruby CSV:**

```ruby
csv = "name,age\n\"Alice,30\nBob,25\nCarol,40"
#                ^ unclosed quote

rows = CSV.parse(csv, headers: true)
rows.length         # => 1  (not 3)
rows.first['name']  # => "Alice,30\nBob,25\nCarol,40"
#                         ^^^ entire remainder of file in one field
```

On a large file this is an OOM risk: the parser accumulates an ever-growing string until EOF or memory exhaustion. There is no field size limit, no timeout, and no error until the file ends.

**With SmarterCSV:**

```ruby
reader = SmarterCSV::Reader.new('data.csv',
  field_size_limit: 10_000,
  on_bad_row: :collect,
)
good_rows = reader.process
# FieldSizeLimitExceeded is collected — processing continues with remaining rows
```

`field_size_limit: N` raises `SmarterCSV::FieldSizeLimitExceeded` as soon as any field or accumulating multiline buffer exceeds N bytes — the runaway parse stops immediately. Additionally, `quote_boundary: :standard` (default since 1.16.0) means mid-field quotes don't toggle quoted mode, reducing the attack surface further.

---

## 9. No Encoding Auto-Detection — Crash or Mojibake

`CSV.read` assumes UTF-8. CSV files exported from Excel on Windows are typically Windows-1252 (CP1252), which encodes accented characters (é, ü, ñ) differently from UTF-8.

**With Ruby CSV — Scenario 1: crash** (the better outcome — at least you know):

```ruby
# Excel export in Windows-1252 encoding, contains "Müller"
rows = CSV.read('excel_export.csv', headers: true)
# => Encoding::InvalidByteSequenceError: "\xFC" from ASCII-8BIT to UTF-8
```

**With Ruby CSV — Scenario 2: silent mojibake** (the worse outcome):

```ruby
# Specifying the wrong encoding suppresses the error
rows = CSV.read('excel_export.csv', headers: true, encoding: 'binary')
rows.first['last_name']                # => "M\xFCller"  ← garbled string
rows.first['last_name'].valid_encoding? # => true  ← Ruby thinks it's fine
```

The mojibake string passes `.valid_encoding?`, passes database validations, gets stored, and surfaces as a display bug in production.

**With SmarterCSV:**

```ruby
rows = SmarterCSV.process('excel_export.csv',
  file_encoding: 'windows-1252:utf-8')
rows.first[:last_name]   # => "Müller"
```

`file_encoding:` accepts Ruby's `'external:internal'` transcoding notation. `force_utf8: true` transcodes to UTF-8 automatically. `invalid_byte_sequence:` controls the replacement character for bytes that can't be transcoded.

---

## Why These Failures Are Dangerous

Every failure in this list is **silent**. No exception, no warning, no log line — the import completes successfully and the data is quietly wrong. That makes them hard to catch in tests and easy to miss in code review.

The root cause is that `CSV.read` is a tokenizer, not a data pipeline. It splits bytes into fields and returns them with no normalization, no validation, and no defensive handling of real-world messiness. Every assumption about what "clean" input looks like is left to the caller.

`CSV.table` fixes exactly one issue out of nine — whitespace in headers — because its `:symbol` converter happens to call `.strip`. Everything else is identical.

These are not obscure edge cases. Extra columns, trailing commas, BOMs, Windows-1252 encoding, duplicate headers, and blank header cells are all common in CSV files exported from Excel, reporting tools, ERP systems, and legacy data pipelines.

---

PREVIOUS: [Migrating from Ruby CSV](./migrating_from_csv.md) | NEXT: [Parsing Strategy](./parsing_strategy.md) | UP: [README](../README.md)
