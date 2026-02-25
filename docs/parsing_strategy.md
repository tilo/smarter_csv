
### Contents

  * [Introduction](./_introduction.md)
  * [Migrating from Ruby CSV](./migrating_from_csv.md)
  * [**Parsing Strategy**](./parsing_strategy.md)
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
  * [Examples](./examples.md)
  * [SmarterCSV over the Years](./history.md)

--------------

# Parsing Strategy

In the real world, you rarely get to choose the quality of the CSV data you need to process. Files come from different systems, different export tools, different people — and they don't always follow the same rules. A header row might have extra whitespace, column separators vary, and quoting conventions differ from one source to the next.

Beyond parsing, consuming CSV data in Ruby and Rails has its own requirements. Working with database records, Sidekiq jobs, or JSON APIs means you need each row as a hash — and with symbol keys rather than strings, because symbols are interned and reused in memory, while duplicate strings allocate new objects for every row. For large CSV files with millions of rows, reading the entire file into memory is not practical. Instead, the data needs to be processed in chunks, where each chunk is an array of hashes that can be bulk-inserted into a database, passed to a background job, or uploaded to S3 — enabling parallel processing without ever holding the full dataset in memory.

SmarterCSV is designed around this reality. Rather than requiring you to know the exact format of your input upfront, it uses sensible defaults and auto-detection to handle the most common variations automatically. Column and row separators are auto-detected, headers are normalized, whitespace is stripped, and numeric values are converted. The output is an array of hashes with symbols as keys — ideal for direct consumption in Ruby and Rails. All of this works out of the box, without configuration.

SmarterCSV auto-detects CSV column and row separators. The same philosophy extends to how quoted fields are parsed. The `quote_escaping: :auto` default means you don't need to know whether your CSV producer uses RFC 4180 doubled quotes or MySQL-style backslash escapes — SmarterCSV figures it out for you, row by row.

The goal is simple: **make the common case work without options, and provide explicit options when you need control.**

## Quote Escaping: The `quote_escaping` Option

CSV files use quote characters (typically `"`) to wrap fields that contain special characters like the column separator or newlines. But there are two common conventions for how a literal quote character is represented *inside* a quoted field:

| Convention | Example field value | How it appears in CSV |
|---|---|---|
| **RFC 4180** (doubled quotes) | `She said "hello"` | `"She said ""hello"""` |
| **MySQL / Unix** (backslash escape) | `She said "hello"` | `"She said \"hello\""` |

The `quote_escaping` option controls which convention SmarterCSV uses when parsing.

## `:auto` (default)

The `:auto` mode handles both conventions automatically. It tries backslash-escape interpretation first. If that produces a malformed result (unclosed quoted field), it falls back to RFC 4180 interpretation.

This means both styles of CSV files work out of the box:

```ruby
# RFC 4180 style — works
csv = %Q{name\n"She said ""hello"""}
SmarterCSV.process(StringIO.new(csv))
# => [{name: 'She said "hello"'}]

# MySQL/Unix style — also works
csv = %Q{name\n"She said \\"hello\\""}
SmarterCSV.process(StringIO.new(csv))
# => [{name: 'She said \\"hello\\"'}]
```

The `:auto` mode also correctly handles fields that end with a literal backslash (a common source of parsing errors, see [Issue #316](https://github.com/tilo/smarter_csv/issues/316)):

```ruby
# Field value is a Windows path ending in backslash
csv = %Q{path,label\n"C:\\Users\\Docs\\",important}
SmarterCSV.process(StringIO.new(csv))
# => [{path: "C:\\Users\\Docs\\", label: "important"}]
```

### How `:auto` works internally

1. **Multiline detection** uses dual counting: it computes both a backslash-aware quote count and an RFC (plain) quote count in a single pass. A line is only considered multiline if *both* counts are odd. This prevents false multiline stitching when a field simply ends with `\"`.

2. **Parsing** tries the backslash-escape interpretation first. If the parser raises `MalformedCSV` (unclosed quote), it retries with RFC 4180 interpretation.

3. The fallback is per-line, so different rows in the same file can use different conventions.

## `:double_quotes`

Strict RFC 4180 mode. Backslash has no special meaning — it is always a literal character. Only `""` (doubled quotes) inside a quoted field represents a single `"`.

Use this when you know your data follows RFC 4180 and want to avoid the small overhead of the try/fallback logic.

```ruby
SmarterCSV.process("file.csv", quote_escaping: :double_quotes)
```

## `:backslash`

MySQL / Unix mode. A backslash before a quote character (`\"`) is treated as an escaped quote — the quote does not close the field. An even number of backslashes before a quote (e.g. `\\"`) means the backslashes are literal and the quote closes normally.

Use this when your data was exported from MySQL or another system that uses backslash escaping.

```ruby
SmarterCSV.process("file.csv", quote_escaping: :backslash)
```

**Note:** In `:backslash` mode, a field like `"abc\"` will raise `MalformedCSV` because the closing quote is escaped, leaving the field unclosed.

## Quote Boundary: The `quote_boundary` Option

Real-world CSV files sometimes contain quote characters in the middle of an unquoted field — for example, a measurement like `6'2"`, a product name like `Intel Core i5 "Raptor Lake"`, or a field with an apostrophe in a poorly-exported file. Under a naive quote parser, any `"` would toggle quoted state, causing the field to be misread and subsequent fields to be garbled.

The `quote_boundary` option controls where SmarterCSV recognizes a quote as a field delimiter.

### `:standard` (default)

In `:standard` mode, two rules apply:

- **Rule 1 — Opening**: a quote only opens a quoted field when it appears at the very start of the field (immediately after the column separator, or at the start of a line). A quote encountered after any other content is treated as a literal character.
- **Rule 2 — Closing**: a quote only closes a quoted field when it is immediately followed by a column separator, a row separator, or end of input. A quote in any other position inside a quoted field is treated as content (enabling RFC 4180 `""` doubled-quote escaping).

```ruby
# Mid-field quote is a literal character — no state change
csv = "product,size\nCore i5 \"Raptor Lake\",medium\n"
SmarterCSV.process(StringIO.new(csv))
# => [{product: 'Core i5 "Raptor Lake"', size: "medium"}]

# Quote at field start opens quoted mode normally
csv = "first,second\n\"hello, world\",other\n"
SmarterCSV.process(StringIO.new(csv))
# => [{first: "hello, world", second: "other"}]

# RFC 4180 doubled quotes work inside a properly opened quoted field
csv = "name\n\"She said \"\"hello\"\"\"\n"
SmarterCSV.process(StringIO.new(csv))
# => [{name: 'She said "hello"'}]
```

`:standard` is the default because treating mid-field quotes as literals matches how most modern CSV parsers (including Ruby's built-in `CSV` library in strict mode) handle malformed-but-common real-world data.

### `:legacy`

In `:legacy` mode, any quote character toggles quoted state regardless of its position in the field. This was the only behavior available before SmarterCSV 1.16.0.

Use `:legacy` only if you have files that were specifically produced to rely on mid-field quote toggling, and you cannot change the source. Note that a mid-field quote with an odd total count will result in an unclosed field and a `MalformedCSV` error under `:legacy` mode.

```ruby
SmarterCSV.process("file.csv", quote_boundary: :legacy)
```

### Interaction with `quote_escaping`

Both options apply simultaneously. `quote_boundary` governs *where* a quote is recognized as a delimiter; `quote_escaping` governs *how* a literal quote is represented *inside* a quoted field. They are independent:

| `quote_boundary` | `quote_escaping` | Effect |
|---|---|---|
| `:standard` | `:auto` (default) | Standard field boundaries + auto-detect escaping style |
| `:standard` | `:double_quotes` | Standard field boundaries + RFC 4180 only |
| `:standard` | `:backslash` | Standard field boundaries + backslash escaping |
| `:legacy` | `:auto` | Old toggle behavior + auto-detect escaping style |

--------------
PREVIOUS: [Migrating from Ruby CSV](./migrating_from_csv.md) | NEXT: [The Basic Read API](./basic_read_api.md)
