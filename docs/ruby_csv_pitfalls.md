
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

Ruby's built-in `CSV` library is for many the go-to — it ships with Ruby and requires no dependencies. But it has failure modes that produce **no exception, no warning, and no indication that anything went wrong**. Your import runs, your tests pass, and your data is quietly wrong.

This page documents ten reproducible ways `CSV.read` (and `CSV.table`) can silently corrupt or lose data, with examples you can run yourself, and how SmarterCSV handles each case.

> **Note on `CSV.table`:** It's a convenience wrapper for `CSV.read` with `headers: true`, `header_converters: :symbol`, and `converters: :numeric`.

---

## At a Glance

| # | Ruby CSV Issue | Failure Mode | SmarterCSV fix | SmarterCSV Details |
|---|-------|-------------|:--------------:|---------|
| 1 | Extra columns silently dropped | Values beyond header count compete for the `nil` key — only the first survives, the rest are discarded | by default ✅ | Default `missing_headers: :auto` auto-generates `:column_N` keys |
| 2 | Duplicate headers — first wins | `.to_h` keeps only the first value for a repeated header; later values silently lost | by default ✅ | Default `duplicate_header_suffix:` → `:score`, `:score2`, `:score3` |
| 3 | Empty headers — `nil` key collision | Blank header cells become `nil` keys; multiple blanks collide and only the first value survives | by default ✅ | Default `missing_header_prefix:` → `:column_1`, `:column_2` |
| 4 | `CSV.table` silently corrupts leading-zero strings via octal | `converters: :numeric` calls `Integer()` which interprets leading zeros as octal — `"00123"` → `83` | by default ✅ | Default `convert_values_to_numeric: true` uses decimal — no octal trap; `convert_values_to_numeric: false` preserves strings exactly |
| 5 | Whitespace in headers ¹ | `" Age"` ≠ `"Age"` — lookup silently returns `nil` | by default ✅ | Default `strip_whitespace: true` strips headers and values |
| 6 | Whitespace around values | `"active  " == "active"` → `false` — leading/trailing spaces or tabs cause status/type checks to silently return wrong results | by default ✅ | Default `strip_whitespace: true` strips all values; set `false` to preserve spaces |
| 7 | `nil` vs `""` for empty fields | Unquoted empty → `nil`, quoted empty → `""` — inconsistent empty checks | by default ✅ | Default `remove_empty_values: true` removes both; `false` normalizes both to `""` |
| 8 | Backslash-escaped quotes (MySQL/Unix) | `\"` treated as field-closing quote — crash or garbled data | by default ✅ | Default `quote_escaping: :auto` handles both RFC 4180 and backslash escaping |
| 9 | TSV file read as CSV — one field per row | Default `col_sep: ","` on a tab-delimited file returns each row as a single string; all column structure lost | by default ✅ | Default `col_sep: :auto` detects the actual delimiter — no option needed |
| 10 | No encoding auto-detection | Non-UTF-8 files either crash or silently produce mojibake | via option | `file_encoding:`, `force_utf8: true`, `invalid_byte_sequence:` |

¹ The one case where `CSV.table` does better than `CSV.read`: its `header_converters: :symbol` option includes `.strip`, so whitespace is removed from headers (#5). Values (#6) are not stripped — `CSV.table` has the same trailing-whitespace problem. For all other issues `CSV.table` is identical to or worse than `CSV.read` — in particular, issue #4 is caused by `CSV.table`'s default `converters: :numeric`.

---

## Why These Failures Are Dangerous

Every failure in this list is **silent**. No exception, no warning, no log line — the import completes successfully and the data is quietly wrong. That makes them hard to catch in tests and easy to miss in code review.

The root cause is that `CSV.read` is a tokenizer, not a data pipeline. It splits bytes into fields and returns them with no normalization, no validation, and no defensive handling of real-world messiness. Every assumption about what "clean" input looks like is left to the caller.

`CSV.table` fixes exactly one issue out of ten — whitespace in headers — because its `:symbol` converter happens to call `.strip`. Everything else is identical or worse.

These are not obscure edge cases. Extra columns, trailing commas, encoding issues, duplicate headers, blank header cells, TSV-vs-CSV confusion, and leading-zero identifiers are all common in CSV files exported from Excel, reporting tools, ERP systems, and legacy data pipelines.

> **Ready to switch?**  ➡️ [Migrating from Ruby CSV](./migrating_from_csv.md)

---

## 1. Extra Columns Without Headers — Values Silently Discarded

When a row has more fields than there are headers, `CSV.read` maps every extra field to the `nil` key. If there are multiple extra fields, they all compete for the same `nil` key — **only the first one survives**, the rest are silently discarded.

```
$ cat example1.csv
   First Name  , Last Name , Age
Alice , Smith,  30, VIP, Gold ,
Bob, Jones,  25
```

**With Ruby CSV:**

```ruby
rows = CSV.read('example1.csv', headers: true).map(&:to_h)
rows.first
# => {"   First Name  " => "Alice ", " Last Name " => " Smith", " Age" => "  30", nil => " VIP"}
#    "Gold" and the trailing empty field are silently lost — only the first extra value survives  ^^^
```

Alice's row has 6 fields but only 3 headers. The extra fields `" VIP"`, `" Gold "`, and `""` (trailing comma) all land on `nil` — only the first survives. No error, no warning.

This is common in real-world exports: tools frequently append audit columns, status flags, or trailing commas that don't correspond to headers.

**`CSV.table` has the same problem.**

**With SmarterCSV:**

```ruby
rows = SmarterCSV.process('example1.csv')
rows.first
# => {first_name: "Alice", last_name: "Smith", age: 30, column_4: "VIP", column_5: "Gold"}
```

The default `missing_headers: :auto` auto-generates distinct names for extra columns using `missing_header_prefix` (default: `"column_"`). The trailing empty field is dropped by the default `remove_empty_values: true` setting. No data loss.

---

## 2. Duplicate Header Names — Second Value Silently Dropped

When two columns share the same header name, `CSV::Row#to_h` keeps only the **first** value. Subsequent values for that header are silently dropped.

```
$ cat example2.csv
score,name,score
95,Alice,87
```

**With Ruby CSV:**

```ruby
rows = CSV.read('example2.csv', headers: true).map(&:to_h)
rows.first
# => {"score" => "95", "name" => "Alice"}
#    ^^^ second score (87) silently lost
```

Common with reporting tool exports that repeat a column (e.g., two date columns both labeled `"Date"`).

**With SmarterCSV:**

```ruby
rows = SmarterCSV.process('example2.csv')
rows.first
# => {score: 95, name: "Alice", score2: 87}
```

* The default `duplicate_header_suffix: ""` disambiguates by appending a counter: `:score`, `:score2`, `:score3`.
* Use `duplicate_header_suffix: '_'` to get `:score_2`, `:score_3`.
* Set `duplicate_header_suffix: nil` to raise `DuplicateHeaders` instead.

---

## 3. Empty Header Fields — `nil` Key Collision

A CSV file with blank header cells (e.g., `name,,age`) gives those columns a `nil` key. Multiple blank headers all collide on `nil` — only the first value survives, the rest are silently lost.

> This is distinct from issue #1. Issue #1 is about extra *data* fields beyond the header count. Issue #3 is about blank cells *in the header row itself* — both map to `nil`, so they share the same collision problem.

```
$ cat example3.csv
name,,,age
Alice,foo,bar,30
```

**With Ruby CSV:**

```ruby
rows = CSV.read('example3.csv', headers: true).map(&:to_h)
rows.first
# => {"name" => "Alice", nil => "foo", "age" => "30"}
#    ^^^ "bar" silently lost — both blank headers map to nil, first value wins
```

`CSV.table` converts named headers to symbols, but blank headers still become `nil`:

```ruby
rows = CSV.table('example3.csv').map(&:to_h)
rows.first
# => {name: "Alice", nil => "foo", age: 30}
#    ^^^ "bar" still silently lost
```

**With SmarterCSV:**

```ruby
rows = SmarterCSV.process('example3.csv')
rows.first
# => {name: "Alice", column_1: "foo", column_2: "bar", age: 30}
```

`missing_header_prefix:` (default `"column_"`) auto-generates names for blank headers: `:column_1`, `:column_2`, etc. No collision, no data loss.

---

## 4. `CSV.table` Silently Corrupts Leading-Zero Strings via Octal

`CSV.table` applies `converters: :numeric` by default, which calls Ruby's `Integer()` on every field that looks like a number. Ruby's `Integer()` follows C literal conventions: **a leading zero means octal**. The result is not just "leading zeros stripped" — the entire number is silently converted to a completely different value.

```
$ cat example4.csv
customer_id,zip_code,amount
00123,01234,99.50
00456,90210,9.99
```

**With Ruby CSV (`CSV.table` or `converters: :numeric`):**

```ruby
rows = CSV.table('example4.csv').map(&:to_h)
rows.first
# => {customer_id: 83, zip_code: 668, amount: 99.5}
#    ^^^ "00123" → 83  (octal 0123 = decimal 83)
#    ^^^ "01234" → 668 (octal 1234 = decimal 668)
```

`"00123"` becomes `83`. `"01234"` becomes `668`. ZIP codes, customer IDs, order numbers, product codes — any field with a leading zero becomes a completely wrong integer. No exception, no warning. The resulting values look plausible and pass all type validations.

`CSV.read` default (no converters) is safe — strings are returned as-is:

```ruby
rows = CSV.read('example4.csv', headers: true).map(&:to_h)
rows.first
# => {"customer_id" => "00123", "zip_code" => "01234", "amount" => "99.50"}
```

The trap is `CSV.table` (which many developers use as the "proper" API) and any explicit use of `converters: :numeric` or `converters: :integer`.

**With SmarterCSV:**

```ruby
# Default (convert_values_to_numeric: true) — decimal conversion, no octal trap
rows = SmarterCSV.process('example4.csv')
rows.first
# => {customer_id: 123, zip_code: 1234, amount: 99.5}

# convert_values_to_numeric: false — preserves strings exactly, including leading zeros
rows = SmarterCSV.process('example4.csv', convert_values_to_numeric: false)
rows.first
# => {customer_id: "00123", zip_code: "01234", amount: "99.50"}
```

SmarterCSV's default `convert_values_to_numeric: true` uses `to_i` / `to_f`, which always treats strings as decimal — no octal interpretation. Use `convert_values_to_numeric: false` when leading zeros must be preserved (ZIP codes, IDs, product codes).

---

## 5. Whitespace in Header Names — Silent `nil` on Lookup

`CSV.read` returns headers exactly as they appear in the file, including leading and trailing whitespace. Code that accesses columns by the expected name silently gets `nil`.

```
$ cat example5.csv
 name , age
Alice,30
```

**With Ruby CSV:**

```ruby
rows = CSV.read('example5.csv', headers: true).map(&:to_h)
rows.first
# => {" name " => "Alice", " age" => "30"}

rows.first['name']   # => nil  ← key is " name ", not "name"
rows.first['age']    # => nil
```

> `CSV.table` mitigates this: the `:symbol` header converter includes `.strip`. This is the one issue where `CSV.table` behaves better than `CSV.read`.

**With SmarterCSV:**

```ruby
rows = SmarterCSV.process('example5.csv')
rows.first
# => {name: "Alice", age: 30}
```

The default setting `strip_whitespace: true` strips leading/trailing whitespace from both headers and values.

---

## 6. Whitespace Around Values — Silent Comparison Failure

`CSV.read` returns field values exactly as they appear in the file — leading spaces, trailing spaces, and tab characters all preserved. Exporters from fixed-width database systems (Oracle `CHAR` columns, COBOL-era systems) routinely pad string fields to a fixed width; other tools leave accidental leading spaces. The values look correct when printed, but equality checks silently return `false`.

This pairs with Example 5 (whitespace in headers): Ruby CSV strips neither headers nor values by default.

```
$ cat example6.csv
name,status,city
Alice,active  ,New York    ← trailing spaces after 'active'
Bob,inactive,Chicago
Carol, active,Boston       ← leading space before 'active'
```

**With Ruby CSV:**

```ruby
rows = CSV.read('example6.csv', headers: true).map(&:to_h)

rows[0]['status']  # => "active  "
rows[2]['status']  # => " active"

rows.select { |r| r['status'] == 'active' }
# => []  ← Alice and Carol are not found. No error raised.
```

The values look fine in logs and `puts` output. The bug only surfaces when the comparison silently returns the wrong result.

**Workaround:** pass `strip: true` to `CSV.read`. This correctly strips spaces and tab characters. Note it also strips intentional leading/trailing spaces from any field — including quoted fields where spaces may be meaningful.

**With SmarterCSV:**

```ruby
rows = SmarterCSV.process('example6.csv')

rows[0][:status]  # => "active"
rows[2][:status]  # => "active"

rows.select { |r| r[:status] == 'active' }.length  # => 2
```

`strip_whitespace: true` (default) strips all leading and trailing whitespace (spaces and tabs) from values. Set `strip_whitespace: false` to preserve spaces when needed.

---

## 7. `nil` vs `""` for Empty Fields — Inconsistent Empty Checks

`CSV.read` treats unquoted empty fields and quoted empty fields differently:

- Unquoted empty (`,,`) → `nil`
- Quoted empty (`,"",`) → `""`

```
$ cat example7.csv
name,city
Alice,
Bob,""
```

**With Ruby CSV:**

```ruby
rows = CSV.read('example7.csv', headers: true).map(&:to_h)

rows[0]['city']        # => nil   (unquoted empty)
rows[1]['city']        # => ""    (quoted empty)

rows[0]['city'].nil?   # => true
rows[1]['city'].nil?   # => false  ← same semantic meaning, different Ruby type
```

Both rows have no city, but your code sees two different things. Any check using `.nil?`, `.blank?`, `.present?`, or `if row['city']` will behave differently depending on how the upstream exporter quoted the empty field.

**With SmarterCSV:**

```ruby
# remove_empty_values: true (default) — both empty cities are dropped from the hash
rows = SmarterCSV.process('example7.csv')
rows[0]   # => {name: "Alice"}
rows[1]   # => {name: "Bob"}

# remove_empty_values: false — both normalized to ""
rows = SmarterCSV.process('example7.csv', remove_empty_values: false)
rows[0]   # => {name: "Alice", city: ""}
rows[1]   # => {name: "Bob",   city: ""}
```

---

## 8. Backslash-Escaped Quotes — MySQL / Unix Dump Format

MySQL's `SELECT INTO OUTFILE`, PostgreSQL `COPY TO`, and many Unix data-pipeline tools escape embedded double quotes as `\"` — not as `""` (the RFC 4180 standard). Ruby's `CSV` only understands RFC 4180, so a backslash before a quote is treated as two separate characters: a literal `\` followed by a `"` that immediately **closes the field**.

```
$ cat example8.csv
name,note
Alice,"She said \"hello\" to everyone"
Bob,"Normal note"
```

**With Ruby CSV — Scenario 1: crash** (at least you know something went wrong):

```ruby
rows = CSV.read('example8.csv', headers: true)
# => CSV::MalformedCSVError: Any value after quoted field isn't allowed in line 2.
```

**With Ruby CSV — Scenario 2: silent garbling** with `liberal_parsing: true`:

```ruby
rows = CSV.read('example8.csv', headers: true, liberal_parsing: true).map(&:to_h)
rows[0]['note']
# => "\"She said \\\"hello\\\" to everyone\""
#    ^^^ outer quotes not stripped; field mis-parsed, extra backslashes included
```

No exception. No warning. The field value is wrong but looks plausible.

**With SmarterCSV:**

```ruby
rows = SmarterCSV.process('example8.csv')
rows[0]   # => {name: "Alice", note: "She said \"hello\" to everyone"}
rows[1]   # => {name: "Bob",   note: "Normal note"}
```

`quote_escaping: :auto` (default) detects and handles both `""` and `\"` escaping row-by-row. No option required. This covers MySQL `SELECT INTO OUTFILE`, PostgreSQL `COPY TO`, and Unix `csvkit`/`awk`-generated files.

---

## 9. TSV File Read as CSV — Entire Row Collapses to One Field

`CSV.read` uses a comma as the default column separator. If the file is actually tab-delimited (TSV) — common with database exports, Excel "Save as Text", and many reporting tools — every row collapses to a single field containing the entire line, tabs included. All column structure is silently lost.

```
$ cat example9.csv    # actually tab-delimited
name	city	score
Alice	New York	95
Bob	Chicago	87
```

**With Ruby CSV:**

```ruby
rows = CSV.read('example9.csv', headers: true).map(&:to_h)
rows.first
# => {"name\tcity\tscore" => "Alice\tNew York\t95"}
#    ^^^ entire header row is one key; entire data row is one value

rows.first['name']   # => nil  ← column unreachable
rows.length          # => 2    ← row count looks right — nothing looks wrong
```

`rows.length` is still 2 and no error is raised. The data is all there — just jammed into one field per row. This is easy to miss in tests that only check row counts or presence of records.

**`CSV.table` has the same problem.**

**With SmarterCSV:**

```ruby
rows = SmarterCSV.process('example9.csv')
rows.first
# => {name: "Alice", city: "New York", score: 95}
```

The default `col_sep: :auto` sniffs the file content and detects the tab separator automatically. No option needed.

---

## 10. No Encoding Auto-Detection — Crash or Mojibake

`CSV.read` assumes UTF-8. CSV files exported from Excel on Windows are typically Windows-1252 (CP1252), which encodes accented characters (é, ü, ñ) differently from UTF-8.

```
$ cat example10.csv
last_name,first_name
Müller,Hans
```

The file is saved in Windows-1252 encoding — `ü` is stored as `\xFC`, not as UTF-8.

**With Ruby CSV — Scenario 1: crash** (the better outcome — at least you know):

```ruby
rows = CSV.read('example10.csv', headers: true)
# => CSV::InvalidEncodingError: Invalid byte sequence in UTF-8 in line 2.
```

**With Ruby CSV — Scenario 2: silent mojibake** (the worse outcome):

```ruby
# Specifying the wrong encoding suppresses the error
rows = CSV.read('example10.csv', headers: true, encoding: 'binary')
rows.first['last_name']                # => "M\xFCller"  ← garbled string
rows.first['last_name'].valid_encoding? # => true  ← Ruby thinks it's fine
```

The mojibake string passes `.valid_encoding?`, passes database validations, gets stored, and surfaces as a display bug in production.

**With SmarterCSV:**

```ruby
rows = SmarterCSV.process('example10.csv',
  file_encoding: 'windows-1252:utf-8')
rows.first[:last_name]   # => "Müller"
```

* `file_encoding:` accepts Ruby's `'external:internal'` transcoding notation.
* `force_utf8: true` transcodes to UTF-8 automatically.
* `invalid_byte_sequence:` controls the replacement character for bytes that can't be transcoded.

---

PREVIOUS: [Migrating from Ruby CSV](./migrating_from_csv.md) | NEXT: [Parsing Strategy](./parsing_strategy.md) | UP: [README](../README.md)
