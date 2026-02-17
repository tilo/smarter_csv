
### Contents

  * [Introduction](./_introduction.md)
  * [**Parsing Strategy**](./parsing_strategy.md)
  * [The Basic Read API](./basic_read_api.md)
  * [The Basic Write API](./basic_write_api.md)
  * [Batch Processing](././batch_processing.md)
  * [Configuration Options](./options.md)
  * [Row and Column Separators](./row_col_sep.md)
  * [Header Transformations](./header_transformations.md)
  * [Header Validations](./header_validations.md)
  * [Data Transformations](./data_transformations.md)
  * [Value Converters](./value_converters.md)

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

--------------
PREVIOUS: [Introduction](./_introduction.md) | NEXT: [The Basic Read API](./basic_read_api.md)
