
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

When having to parse CSV files, many developers go straight to the Ruby `CSV` library — it ships with Ruby and requires no dependencies.

But it comes at the cost of boilerplate post-processing you have to write, test, and maintain yourself. Worse, there are some failure modes that produce **no exception, no warning, and no indication that anything went wrong**. Your import runs, your tests pass, and your data is quietly wrong.

`CSV.read` is fine for small, trusted, well-formed files — particularly when you control the source. This page is about what can happen with **messy real-world files your partners produce, or users upload** — ten reproducible ways `CSV.read` and `CSV.table` can silently corrupt or lose data, with examples you can run yourself, and how SmarterCSV handles each case.

> Not all ten may be equally surprising — some are odd behavior that bites you anyway, others are genuine traps. All ten are silent.

---

> 💡 **Want to follow along?** Download the [example CSV files](https://raw.githubusercontent.com/tilo/articles/main/ruby/smarter_csv/10-ways-ruby_csv-can-silently-corrupt-or-lose-your-data/images/10-ways-ruby_csv-can-silently-corrupt-or-lose-your-data-examples.tgz) and run the examples locally.

---

## At a Glance

| # | Severity | Ruby CSV Issue | Failure Mode | SmarterCSV fix | SmarterCSV Details |
|---|:--------:|-------|-------------|:--------------:|---------|
| 1 | 🔴 | Extra columns silently dropped | Values beyond header count compete for the `nil` key — only the first survives, the rest are discarded | by default ✅ | Default `missing_headers: :auto` auto-generates `:column_N` keys |
| 2 | 🔴 | Duplicate headers — first wins | `.to_h` keeps only the first value for a repeated header; later values silently lost | by default ✅ | Default `duplicate_header_suffix:` → `:score`, `:score2`, `:score3` |
| 3 | 🔴 | Empty headers — `nil` key collision | Blank header cells become `nil` keys; multiple blanks collide and only the first value survives | by default ✅ | Default `missing_header_prefix:` → `:column_1`, `:column_2` |
| 4 | 🔴 | `converters: :numeric` silently corrupts leading-zero values as octal ¹ | `Integer()` interprets leading zeros as octal — `"00123"` → `83` ❌ | by default ✅ | Default `convert_values_to_numeric: true` uses decimal — no octal trap; `convert_values_to_numeric: false` preserves strings exactly |
| 5 | 🟡 | Whitespace in headers ² | `" Age"` ≠ `"Age"` — lookup silently returns `nil` | by default ✅ | Default `strip_whitespace: true` strips headers and values |
| 6 | 🟡 | Whitespace around values | `"active  " == "active"` → `false` — leading/trailing spaces or tabs cause status/type checks to silently return wrong results | by default ✅ | Default `strip_whitespace: true` strips all values; set `false` to preserve spaces |
| 7 | 🟠 | `nil` vs `""` for empty fields | Unquoted empty → `nil`, quoted empty → `""` — inconsistent empty checks | by default ✅ | Default `remove_empty_values: true` removes both; `false` normalizes both to `""` |
| 8 | 🟠 | Backslash-escaped quotes (MySQL/Unix) | `\"` treated as field-closing quote — crash or garbled data | by default ✅ | Default `quote_escaping: :auto` handles both RFC 4180 and backslash escaping |
| 9 | 🔴 | TSV file read as CSV — completely breaks ❌ | Default `col_sep: ","` on a tab-delimited file returns each row as a single string; all column structure lost | by default ✅ | Default `col_sep: :auto` detects the actual delimiter — no option needed |
| 10 | 🔴 | No encoding auto-detection | Non-UTF-8 files either crash or silently produce mojibake | via option | `file_encoding:`, `force_utf8: true`, `invalid_byte_sequence: ''` |

¹ Issue #4 can be triggered two ways: `CSV.table` enables `converters: :numeric` by default (no opt-in required), and `CSV.read` triggers the same corruption when passed `converters: :numeric` explicitly. Either way, any leading-zero string field — ZIP codes, customer IDs, product codes — is silently converted to a wrong integer.

² The one case where `CSV.table` does better than `CSV.read`: its `header_converters: :symbol` option includes `.strip`, so whitespace is removed from headers (#5). Values (#6) are not stripped — `CSV.table` has the same whitespace-around-values problem. For all other issues `CSV.table` is identical to or worse than `CSV.read`.

> `CSV.table` is a convenience wrapper for `CSV.read` with `headers: true`, `header_converters: :symbol`, and `converters: :numeric`.

---

## The Real Cost of Handling This Yourself

Experienced users of `CSV.read` know some of these gotchas and handle them in post-processing — but not all of them can be: some are serious bugs that will silently corrupt your data regardless. And even for the ones you can handle, manual post-processing has five hidden costs:

* **You hand-craft boilerplate for every use case.** The right fix for whitespace differs when headers have spaces vs. values have spaces vs. both. Encoding handling depends on the source system. There is no generic post-processing snippet — you write a slightly different version every time.

* **You have to remember all of it, every time.** Every new import, service, or data source needs the same gotchas handled — consistently. But boilerplate doesn't enforce itself. A fix you wrote for one importer doesn't automatically apply to the next. The gotchas don't announce themselves — you only catch them if you remember to look.

* **Your boilerplate is probably undertested.** Post-processing code that wraps `CSV.read` rarely gets the same test coverage as business logic. Developers don't think of it as the risky part. Data edge cases — files with blank headers, leading-zero IDs, quoted empty fields, mixed encoding — don't make it into the test suite until they cause a production incident. You don't know what your boilerplate misses until a file breaks it.

> ❓ Do your tests for your CSV wrapper just test the mechanics, or include data corner cases?

* **Your benchmarks probably don't include the boilerplate code.** When you chose `CSV.read`, you probably looked at raw parsing performance — but did you measure the end-to-end cost of your post-processing? Whitespace stripping, header cleanup, empty normalization: none of that is free. Your end-to-end data pipeline is much slower than what you initially measured.

* **One library that handles it predictably and performant is worth more than the sum of its parts.** The value isn't "these ten cases are covered." It is that you stop maintaining a bespoke cleaning pipeline, stop writing one-off fixes after production surprises, and don't have to worry about test coverage or performance - you can trust that the default behavior handles edge cases sensibly — without silently damaging your data.

Predictable behavior in a well-tested library beats hand-crafted boilerplate that anticipates fewer edge cases.

---

## Why These Failures Are Dangerous

**Every single failure in this list is silent.** No exception, no warning, no log line — your import completes successfully and your data is quietly wrong. That's what makes these issues so dangerous: they don't surface in tests, they don't cause immediate errors, and they're easy to miss during code review.

The root cause is that `CSV.read` is a **tokenizer**, not a data pipeline. It splits bytes into fields and hands them back with no normalization, no validation, and no defensive handling of real-world messiness. Every assumption about what "clean" input looks like is left to the caller.

Issue #4 deserves special mention: `CSV.table`'s default `converters: :numeric` silently turns `"00123"` into `83`³ and `"01234"` into `668`³ — values that look like perfectly valid integers. ZIP codes, customer IDs, and product codes are quietly replaced with wrong numbers that pass every validation, get stored in your database, and are indistinguishable from real data until someone notices the numbers don't match.

These aren't obscure edge cases. Extra columns, trailing commas, Windows-1252 encoding, duplicate headers, blank header cells, TSV-vs-CSV confusion, leading-zero identifiers, and whitespace-padded values are all common in CSV files exported from Excel, reporting tools, ERP systems, and legacy data pipelines. If your application accepts user-uploaded CSV files, you will encounter these.

The defensive post-processing code required to handle all ten cases correctly — octal-safe numeric conversion, whitespace normalization, duplicate header disambiguation, extra column naming, consistent empty value handling, backslash quote escaping, delimiter auto-detection, encoding detection — is non-trivial to write, test, and maintain. Most applications never bother, because the failures are silent.

³ These aren't rounding errors or truncations — they are completely different numbers. [Octal](https://en.wikipedia.org/wiki/Octal) is a base-8 number system from the early days of computing, still used in low-level Unix file permissions and C integer literals. It has no place in CSV data. No spreadsheet, ERP system, or database exports ZIP codes or customer IDs in octal — but Ruby CSV silently assumes that's exactly what a leading zero means.

Read on for a detailed explanation and reproducible example for each issue.

---

## 1. Extra Columns Without Headers — Values Silently Discarded

When a row has more fields than there are headers, `CSV.read` maps every extra field to the `nil` key. If there are multiple extra fields, they all compete for the same `nil` key — **only the first one survives**, the rest are silently discarded.

```
$ cat example1.csv
   First Name  , Last Name , Age
Alice , Smith,  30, VIP, Gold ,
Bob, Jones,  25
```

```ruby
rows = CSV.read('example1.csv', headers: true).map(&:to_h)
rows.first
# => {
#       "   First Name  " => "Alice ",
#           " Last Name " => " Smith",
#                 " Age" => "  30",
#                    nil => " VIP"
#                    ^^^^^^^^^^^^^
#  data from unnamed column with "Gold" is silently lost
# }
```

Alice's row has 6 fields but only 3 headers. The extra fields `" VIP"`, `" Gold"`, and `""` (trailing comma) all land on `nil` — only the first one wins. No error, no warning.

This is common in real-world exports: tools frequently append audit columns, status flags, or trailing commas that don't correspond to headers.

**`CSV.table` has the same problem.**

**SmarterCSV:** The default `missing_headers: :auto` auto-generates distinct names for extra columns using `missing_header_prefix` (default: `"column_"`). The trailing empty field is dropped by the default `remove_empty_values: true` setting. No data loss.

```ruby
rows = SmarterCSV.process('example1.csv')
rows.first
# => {
#     first_name: "Alice",
#      last_name: "Smith",
#            age: 30,
#       column_4: "VIP",
#       column_5: "Gold"
#       ^^^^^^^^^^^^^^^^
#  extra data columns are handled, no data is lost
# }
```

---

## 2. Duplicate Header Names — Second Value Silently Dropped

When two columns share the same header name, `CSV::Row#to_h` keeps only the **first** value. Later values are silently dropped.

```
$ cat example2.csv
score,name,score
95,Alice,87
```

```ruby
rows = CSV.read('example2.csv', headers: true).map(&:to_h)
rows.first
# => {"score" => "95", "name" => "Alice"}
#    ^^^ second score (87) silently lost
```

Common with reporting tool exports that repeat a column (e.g., two date columns both labeled `"Date"`).

**`CSV.table` has the same problem.**

**SmarterCSV:** disambiguates duplicate headers by appending a number directly: `:score`, `:score2`, `:score3`.

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

A CSV file with blank header fields (e.g., `name,,age`) gives those columns a `nil` key. Multiple blank headers all collide on `nil` — same overwrite problem as issue #1, and only the first value survives.

> Note: this is distinct from issue #1. Issue #1 is about extra *data* fields beyond the header count, which get keyed under `nil`. Issue #3 is about blank cells *in the header row itself*, which also get keyed under `nil`.

```
$ cat example3.csv
name,,,age
Alice,foo,bar,30
```

```ruby
rows = CSV.read('example3.csv', headers: true).map(&:to_h)
rows.first
# => {"name" => "Alice", nil => "foo", "age" => "30"}
#    ^^^ "bar" silently lost — both blank headers map to nil, first value wins
```

`CSV.table` has the same `nil` key collision:

```ruby
rows = CSV.table('example3.csv').map(&:to_h)
rows.first
# => {name: "Alice", nil => "foo", age: 30}
#    ^^^ "bar" still silently lost
```

**SmarterCSV:** `missing_header_prefix:` (default `"column_"`) auto-generates names for blank headers: `:column_1`, `:column_2`, etc. No collision, no data loss.

```ruby
rows = SmarterCSV.process('example3.csv')
rows.first
# => {name: "Alice", column_1: "foo", column_2: "bar", age: 30}
```

---

## 4. `converters: :numeric` Silently Corrupts Leading-Zero Values as Octal

`converters: :numeric` When numbers have leading zeroes, the result does not just strip them - the entire number is silently converted to a completely different value³ that looks plausible but is incorrect ❌ .

`CSV.table` enables `converters: :numeric` by default without any opt-in, **triggering the bug by default**. `CSV.read` is safe by default, but triggers the same corruption when `converters: :numeric` (or `converters: :integer`) is passed explicitly.

```
$ cat example4.csv
customer_id,zip_code,amount
00123,01234,99.50
00456,90210,9.99
```

**With Ruby CSV:**

```ruby
# CSV.table — converters: :numeric on by default, no opt-in needed
rows = CSV.table('example4.csv').map(&:to_h)
rows.first
# => {customer_id: 83, zip_code: 668, amount: 99.5}
#    ^^^ "00123" → 83  (octal 0123 = decimal 83)
#    ^^^ "01234" → 668 (octal 1234 = decimal 668)

# CSV.read with explicit converters: :numeric — same result
rows = CSV.read('example4.csv', headers: true, converters: :numeric).map(&:to_h)
rows.first
# => {"customer_id" => 83, "zip_code" => 668, "amount" => 99.5}
```

`"00123"` becomes `83`. `"01234"` becomes `668`. ZIP codes, customer IDs, order numbers, product codes — any field with a leading zero becomes a completely wrong integer. No exception, no warning. The resulting values look plausible and pass all type validations.

`CSV.read` without converters is safe — strings are returned as-is:

```ruby
rows = CSV.read('example4.csv', headers: true).map(&:to_h)
rows.first
# => {"customer_id" => "00123", "zip_code" => "01234", "amount" => "99.50"}
```

**SmarterCSV:**

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

```ruby
rows = CSV.read('example5.csv', headers: true).map(&:to_h)
rows.first
# => {" name " => "Alice", " age" => "30"}

rows.first['name']   # => nil  ← silent miss; key is " name ", not "name"
rows.first['age']    # => nil
```

**`CSV.table` mitigates this:** ² the `:symbol` header converter includes `.strip`, so whitespace is removed from headers. This is the one issue where `CSV.table` behaves better than `CSV.read`.

**SmarterCSV:**

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

```ruby
rows = CSV.read('example6.csv', headers: true).map(&:to_h)

rows[0]['status']  # => "active  "
rows[2]['status']  # => " active"

rows.select { |r| r['status'] == 'active' }
# => []  ← Alice and Carol are not found. No error raised.
```

The values look fine in logs and `puts` output. The bug only surfaces when the comparison silently returns the wrong result.

**Workaround:** pass `strip: true` to `CSV.read`. This correctly strips spaces and tab characters. Note it also strips intentional leading/trailing spaces from any field — including quoted fields where spaces may be meaningful.

**`CSV.table` has the same problem** — its `:symbol` converter strips header names but does not touch field values.

**SmarterCSV:**

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

```ruby
rows = CSV.read('example7.csv', headers: true).map(&:to_h)

rows[0]['city']        # => nil   (unquoted empty)
rows[1]['city']        # => ""    (quoted empty)

rows[0]['city'].nil?   # => true
rows[1]['city'].nil?   # => false  ← same semantic meaning, different Ruby type
```

Both rows have no city. But your code sees two different things. Any check using `.nil?`, `.blank?`, `.present?`, or a simple `if row['city']` will behave differently depending on how the upstream exporter happened to quote the empty field. No two exporters agree on this.

**`CSV.table` has the same problem.**

**SmarterCSV:** `remove_empty_values: true` (default) removes both from the hash. With `remove_empty_values: false`, both are normalized to `""`. Consistent either way.

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

MySQL's `SELECT INTO OUTFILE`, PostgreSQL `COPY TO`, and many Unix data-pipeline tools escape embedded double quotes as `\"` — not as `""` (the RFC 4180 standard). Ruby's `CSV` only understands the RFC 4180 convention, so a backslash before a quote is treated as two separate characters: a literal `\` followed by a `"` that immediately **closes the field**.

```
$ cat example8.csv
name,note
Alice,"She said \"hello\" to everyone"
Bob,"Normal note"
```

**Scenario 1 — crash** (at least you know something went wrong):

```ruby
rows = CSV.read('example8.csv', headers: true)
# => CSV::MalformedCSVError: Any value after quoted field isn't allowed in line 2.
```

**Scenario 2 — silent garbling** with `liberal_parsing: true`:

```ruby
rows = CSV.read('example8.csv', headers: true, liberal_parsing: true)
rows[0]['note']   # => 'She said \"hello\" to everyone'
```

No exception. No warning. The note field has extra wrapping quotes and mangled escaping — it won't compare, display, or serialize correctly.

**`CSV.table` has the same problem** — and adding `liberal_parsing: true` makes it silently worse.

**SmarterCSV:** `quote_escaping: :auto` (default since 1.0) detects and handles both `""` and `\"` escaping row-by-row. No option required.

```ruby
rows = SmarterCSV.process('example8.csv')
rows[0]   # => {name: "Alice", note: 'She said \"hello\" to everyone'}
rows[1]   # => {name: "Bob",   note: "Normal note"}
```

---

## 9. TSV File Read as CSV — Completely Breaks ❌

`CSV.read` defaults to `col_sep: ","`. When given a tab-delimited file (TSV), it finds no commas and treats each entire row as a single field. The header row becomes one giant key; each data row becomes one giant value. All column structure is silently lost — no error, no warning, and `rows.length` looks correct.

```
$ cat example9.csv
name	city	score
Alice	New York	95
Bob	Chicago	87
```

```ruby
rows = CSV.read('example9.csv', headers: true).map(&:to_h)

rows.length           # => 2  (looks right — but...)
rows.first.keys       # => ["name\tcity\tscore"]  ← entire header is one key
rows.first['name']    # => nil  ← column unreachable
rows.first.values     # => ["Alice\tNew York\t95"]  ← entire row is one value
```

This can happen when users upload TSV instead of CSV - the file name could still be `.csv`, so indistinguishable from actual CSV data.

**`CSV.table` has the same problem.**

**SmarterCSV:**

```ruby
rows = SmarterCSV.process('example9.csv')
# col_sep: :auto detects the tab separator automatically

rows.first
# => {name: "Alice", city: "New York", score: 95}
```

`col_sep: :auto` (default) samples the file and detects the actual delimiter. No option required.

---

## 10. No Encoding Auto-Detection — Crash or Mojibake

`CSV.read` assumes UTF-8. CSV files exported from Excel on Windows are typically Windows-1252 (CP1252), which encodes accented characters (é, ü, ñ) differently from UTF-8.

```
$ cat example10.csv
last_name,first_name
Müller,Hans
```

The file is saved in Windows-1252 encoding — `ü` is stored as `\xFC`, not as UTF-8.

**Scenario 1 — crash** (the better outcome — at least you know):

```ruby
rows = CSV.read('example10.csv', headers: true)
# => CSV::InvalidEncodingError: Invalid byte sequence in UTF-8 in line 2.
```

**Scenario 2 — silent mojibake** (the worse outcome):

```ruby
# Specifying the wrong encoding suppresses the error
rows = CSV.read('example10.csv', headers: true, encoding: 'binary')
rows.first['last_name']                # => "M\xFCller"  ← garbled string
rows.first['last_name'].valid_encoding? # => true  ← Ruby thinks it's fine!
```

The mojibake string passes `.valid_encoding?`, passes database validations, gets stored, and surfaces as a display bug weeks later in production.

**`CSV.table` has the same problem.**

**SmarterCSV:** `file_encoding:` accepts Ruby's `'external:internal'` transcoding notation; `force_utf8: true` transcodes to UTF-8 automatically; `invalid_byte_sequence: ''` controls the replacement character for bytes that can't be transcoded, e.g. `''`.

```ruby
rows = SmarterCSV.process('example10.csv',
  file_encoding: 'windows-1252:utf-8')
rows.first[:last_name]   # => "Müller"
```

---

## The Alternative

```ruby
gem 'smarter_csv'
```

```ruby
# Before
rows = CSV.read('data.csv', headers: true).map(&:to_h)

# After
rows = SmarterCSV.process('data.csv')
```

SmarterCSV handles nine of the ten cases out of the box — octal-safe numeric conversion, whitespace normalization, duplicate header disambiguation, extra column naming, consistent empty value handling, backslash quote escaping, and delimiter auto-detection.

The remaining one (encoding control) requires explicit opt-in options, but the building blocks are there. No boilerplate, no post-processing pipeline, no silent data loss.

> **Ready to switch?** → [Migrating from Ruby CSV](./migrating_from_csv.md)

---

PREVIOUS: [Migrating from Ruby CSV](./migrating_from_csv.md) | NEXT: [Parsing Strategy](./parsing_strategy.md) | UP: [README](../README.md)
