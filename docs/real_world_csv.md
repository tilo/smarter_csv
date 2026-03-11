
### Contents

  * [Introduction](./_introduction.md)
  * [Migrating from Ruby CSV](./migrating_from_csv.md)
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
  * [**Real-World CSV Files**](./real_world_csv.md)
  * [Examples](./examples.md)
  * [SmarterCSV over the Years](./history.md)

---

# Real-World CSV Files in Production

CSV is the most common data exchange format in enterprise software — and also one of the most inconsistently implemented. This page documents what you will actually encounter when processing production CSV files, and how SmarterCSV handles each case.

## Status Legend

| Symbol | Meaning |
|--------|---------|
| ✅ | Handled automatically — no configuration needed |
| 🔘 | Handled — but requires the user to specify an option |
| ❌ | Not handled — caller must pre-process or work around |

---

## Encoding & BOM

Real-world files come from dozens of different systems, each with their own default encoding. Excel in particular is notorious for writing UTF-8 files with a Byte Order Mark (BOM) that trips up many parsers.

| Issue | Status | Notes |
|-------|--------|-------|
| UTF-8 with BOM (`\xEF\xBB\xBF`) | ✅ | Stripped automatically from the first line. Excel always writes this. |
| `\r\n` CRLF line endings | ✅ | Auto-detected. The default on Windows and most enterprise exports. |
| `\r` only (classic Mac) | ✅ | Auto-detected. Rare today but still seen in legacy pipelines. |
| Windows-1252 / Latin-1 | 🔘 | Specify `file_encoding: 'windows-1252'`. Common in European financial exports, older SAP systems, QuickBooks. |
| UTF-16 LE with BOM | 🔘 | Specify `file_encoding: 'utf-16le'`. Some Microsoft SQL Server and Access exports default to this. |
| Shift-JIS / EUC-JP | 🔘 | Specify `file_encoding: 'shift_jis'` or `'euc-jp'`. Japanese ERP and POS systems. |

---

## Quoting & Escaping

Two competing quoting conventions exist in the wild and are both common: RFC 4180 (used by Excel) and backslash escaping (used by MySQL, PostgreSQL). SmarterCSV defaults to `:auto` mode which tries backslash first and falls back to RFC 4180.

| Issue | Status | Notes |
|-------|--------|-------|
| RFC 4180 double-quote escaping (`""`) | ✅ | The Excel standard. Handled by `quote_escaping: :auto` (default). |
| Backslash escaping (`\"`) | ✅ | Used by MySQL `SELECT INTO OUTFILE`, `mysqldump`, PostgreSQL `COPY`. Handled by `:auto` default. |
| Newlines inside quoted fields | ✅ | Multi-line field stitching. Common in address fields, notes, and CRM comment exports. |
| Mid-field quote characters (`5'10"`, inch marks, apostrophes) | ✅ | `quote_boundary: :standard` (default since 1.16.0) only recognizes quotes at field boundaries. Mid-field quotes are treated as literal characters. |
| Semicolon-delimited files mislabeled as CSV | ✅ | `col_sep: :auto` (default) detects the actual separator. Common in European locales where comma is the decimal separator. |
| Tab-delimited TSV files | ✅ | `col_sep: :auto` detects tabs. Common in bioinformatics and some government data portals. |

---

## Header Quirks

Headers in production files are rarely as clean as you'd expect. They carry units, source system field names, BOM characters, duplicates, and sometimes no headers at all.

| Issue | Status | Notes |
|-------|--------|-------|
| BOM on first header field | ✅ | Stripped automatically. Without this, the first key would be `:\xEF\xBB\xBFname` instead of `:name`. |
| Duplicate headers | ✅ | Disambiguated using `duplicate_header_suffix` (default `''` → `:email`, `:email_2`, `:email_3`). |
| Empty or whitespace-only headers | ✅ | Auto-named using `missing_header_prefix` (default `column_`) → `:column_1`, `:column_2`. Values are never silently dropped. |
| Trailing comma on header row (phantom empty column) | ✅ | The phantom column is auto-named just like any other empty header. |
| Headers with spaces and special characters (`Revenue (USD)`) | ✅ | Spaces and dashes normalized to underscores → `:revenue_(usd)`. Parentheses, slashes, etc. are preserved. |
| Extra data columns beyond the header row | ✅ | Auto-generates `column_N` names for extra fields. Controlled by `missing_headers:` option. |
| No header row at all | 🔘 | Use `headers_in_file: false, user_provided_headers: [:col1, :col2, ...]`. Common in raw database dumps and fixed-format legacy exports. |

---

## Numeric & Data Type Landmines

Numeric conversion is one of the most common sources of data loss. SmarterCSV converts values that look like numbers by default — which is correct for most cases — but certain fields must be excluded explicitly.

| Issue | Status | Notes |
|-------|--------|-------|
| Integer and float conversion | ✅ | `convert_values_to_numeric: true` (default). `"42"` → `42`, `"3.14"` → `3.14`. |
| Currency symbols in values (`$1,234.56`, `€1.234,56`) | ✅ / 🔘| Won't match the numeric pattern — safely left as a string. Use `value_converters` if numeric value is needed.|
| Percentage values (`12.5%`) | ✅ / 🔘| Won't match the numeric pattern — safely left as a string. Use `value_converters` if numeric value is needed.|
| Leading zeros (ZIP codes, phone numbers, SKUs, account numbers) | 🔘 | `convert_values_to_numeric: { except: [:zip, :phone, :sku] }`. Without this, `"01234"` becomes `1234`. One of the most common silent data loss bugs in CSV processing! US ZIP codes have leading zeroes. |
| NULL / empty value variants (`NULL`, `\N`, `N/A`, `(null)`, `#N/A`) | 🔘 | Use `nil_values_matching: /\A(NULL\\|\\N\|N\/A\|#N\/A\|\\(null\\))\z/i`. Without configuration these are left as literal strings. |
| Date values (`2023-01-15`, `01/02/2023`, `Jan 2, 2023`) | 🔘 | Use `value_converters` with a date parsing lambda. SmarterCSV does not auto-convert dates — format ambiguity (`01/02/2023` = Jan 2 or Feb 1?) makes auto-conversion unsafe. |
| Boolean variants (`Y/N`, `Yes/No`, `TRUE/FALSE`, `1/0`, `X/` in SAP) | 🔘 | Use `value_converters` for the relevant columns. |
| European number format (`1.234,56` meaning 1234.56) | 🔘 | Use a value_converter that swaps dot and comma before parsing. Common in German, French, Italian, and Spanish exports. |

---

## File Size & Structure

| Issue | Status | Notes |
|-------|--------|-------|
| Millions of rows | ✅ | Use `chunk_size: N` for batch processing. SmarterCSV streams the file and never loads it entirely into memory. |
| Gigabyte-sized files | ✅ | Streaming architecture. Memory usage is proportional to chunk size, not file size. |
| Single-column CSV files | ✅ | `col_sep: :auto` handles files with no detected separator gracefully (fixed in issue #222). |
| Ragged rows — fewer fields than headers | ✅ | Missing trailing fields produce no key in the hash. Combined with `remove_empty_values: true` (default), short rows are handled cleanly. |
| Ragged rows — more fields than headers | ✅ | Extra columns are auto-named `column_N` via `missing_header_prefix`. |
| Empty or whitespace-only file | ✅ | Raises `SmarterCSV::EmptyFileError` with a clear message instead of a cryptic internal error. |

---

## Enterprise & Application-Specific Patterns

### Databases & Data Warehouses

| Source | Issue | Status | Notes |
|--------|-------|--------|-------|
| MySQL `SELECT INTO OUTFILE` | Backslash quote escaping | ✅ | `quote_escaping: :auto` default. |
| PostgreSQL `COPY TO` | Backslash quote escaping, `\N` for NULL | ✅ / 🔘 | Escaping handled automatically; `\N` as nil requires `nil_values_matching`. |
| SEC EDGAR | Pipe-delimited, UTF-8, clean format | ✅ | `col_sep: :auto` detects the pipe separator. |
| UNIX DB Dumps† | CTRL-A col separator, CTRL-B row separator, `#` comment lines | 🔘 | `col_sep: "\cA", row_sep: "\cB", comment_regexp: /^#/` |

### ERP & CRM

| Source | Issue | Status | Notes |
|--------|-------|--------|-------|
| SAP ALV / IDOC exports | Space-padded fixed-width fields | ✅ | `strip_whitespace: true` (default) trims all field values. |
| SAP BW/BEx | Very wide exports (300–500+ columns) | ✅ | No column count limit. |
| Salesforce reports | Trailing empty columns, quoted address fields with newlines | ✅ | Both handled by default. |

### Spreadsheets

| Source | Issue | Status | Notes |
|--------|-------|--------|-------|
| Excel `Save As CSV` | UTF-8 BOM, RFC 4180 quoting, 1,048,576 row limit | ✅ | BOM stripped, quoting handled. Row limit is an Excel constraint — SmarterCSV will parse whatever Excel wrote. |

### Finance & Banking

| Source | Issue | Status | Notes |
|--------|-------|--------|-------|
| Stripe / Coinbase / modern fintechs | Clean UTF-8 CSV, ISO 8601 dates, no BOM | ✅ | No special configuration needed. |
| Bank statement exports (Chase, Wells Fargo, Barclays, …) | Metadata preamble rows before the header (account number, date range, institution name) | 🔘 | Use `skip_lines: N` to skip the preamble. N varies by bank and may change with format updates. |
| Accounting negative notation | `(1,234.56)` instead of `-1234.56` — used by QuickBooks, Xero, SAP, and most bank exports | 🔘 | Use a `value_converters` lambda: `->(v) { v&.match?(/\A\(.*\)\z/) ? -v.gsub(/[(),]/, '').to_f : v }` |
| PayPal transaction exports | Preamble rows, mixed currency/amount columns, locale-specific date format | 🔘 | Use `skip_lines:` for preamble; use `value_converters` for dates and signed amounts. |
| Bloomberg / Refinitiv terminal exports | `\|` separator, `N.A.` for nulls, proprietary date formats | 🔘 | `col_sep: "\|"`, `nil_values_matching: /\AN\.A\.\z/`, `value_converters` for dates. |
| QuickBooks exports | Windows-1252 encoding, currency-formatted values | 🔘 | Specify `file_encoding: 'windows-1252'`. Currency values like `"$1,234.56"` stay as strings. |

### Government & Public Data

| Source | Issue | Status | Notes |
|--------|-------|--------|-------|
| Government open data portals | Semicolons as separator, Latin-1, inconsistent quoting | ✅ / 🔘 | `col_sep: :auto` handles semicolons; specify `file_encoding:` if non-UTF-8. |
| US Census Bureau | Very large files (millions of rows), heavily coded values | ✅ | Use `chunk_size:` for memory-efficient processing. |
| US Treasury / USASpending.gov | Large files, many empty columns, dollar amounts as plain strings | ✅ | Works out of the box; `remove_empty_values: true` (default) drops empty columns. |
| World Bank / IMF data exports | 4–5 preamble rows (title, source, notes) before the header | 🔘 | `skip_lines: N` to skip the preamble. N is typically 4 for World Bank, 5 for IMF. |
| Australian ABS (Bureau of Statistics) | UTF-8 BOM, preamble metadata rows before the header | 🔘 | BOM stripped automatically; use `skip_lines: N` for the preamble. |

### Healthcare & Life Sciences

| Source | Issue | Status | Notes |
|--------|-------|--------|-------|
| HL7 / FHIR flattened exports | Very wide files (100+ columns), many empty fields, cryptic column names (`component_0_valueQuantity_value`) | ✅ | Parses fine. `remove_empty_values: true` (default) drops empty fields automatically. |
| Epic / Cerner EHR exports | Windows-1252 encoding, locale-specific date formats | 🔘 | `file_encoding: 'windows-1252'`; use `value_converters` for date columns. |
| Lab instrument exports (Roche, Abbott, Siemens) | Semicolon separator (European instruments), preamble rows with instrument metadata | 🔘 | `col_sep: :auto` detects the separator; `skip_lines: N` for the preamble. |
| DICOM-SR flattened to CSV | Nested structured report data squashed into column names | ✅ | Parses fine. Data model is messy but no special configuration needed. |
| FDA adverse event / MedWatch exports | Pipe-delimited, `null` literal strings, long free-text fields with embedded newlines | 🔘 | `col_sep: "\|"`, `nil_values_matching: /\Anull\z/i`; embedded newlines handled automatically. |
| Bioinformatics (VCF-derived) | Thousands of columns (one sample per column) | ✅ | No column count limit in the parsing hot path. |

### E-commerce & Survey Tools

| Source | Issue | Status | Notes |
|--------|-------|--------|-------|
| Shopify / WooCommerce | Pipe-delimited values within a field (`tag1\|tag2\|tag3`) | 🔘 | Use `value_converters` to split on `\|` for the relevant column. |
| Qualtrics / SurveyMonkey | 200–800 columns, multi-row headers, HTML in values | 🔘 | Multi-row headers require pre-processing; HTML in values left as-is (use value_converters to strip). |

### Legacy & Unusual Formats

| Source | Issue | Status | Notes |
|--------|-------|--------|-------|
| Apple iTunes DB export† | CTRL-A col separator, CTRL-B row separator, `#` comment lines | 🔘 | `col_sep: "\cA", row_sep: "\cB", comment_regexp: /^#/` |

### I/O Patterns

| Source | Issue | Status | Notes |
|--------|-------|--------|-------|
| Gzipped CSV (`.csv.gz`) | Compressed file | 🔘 | Decompress and pass the resulting IO object: `SmarterCSV.process(Zlib::GzipReader.open(path))`. |
| HTTP streaming | Parsing from a live HTTP response | 🔘 | Pass any IO-compatible object that responds to `#gets`. |

†: Legacy Apple DB Dump and older UNIX data dumps use ASCII control characters as delimiters:

```
col_sep = "\x01" # CTRL-A
row_sep = "\x02" # CTRL-B
comment_prefix = "#"
```

---

## Pathological Cases ❌

These formats have structural problems that no CSV parser can transparently resolve. Pre-processing the file before passing it to SmarterCSV is the only reliable solution.

| Issue | Why it breaks | Workaround |
|-------|--------------|------------|
| Mixed line endings within one file | Row separator is detected once from the first N bytes. A file mixing `\r\n` and `\n` will produce rows with stray `\r` on some values. | Pre-process with `dos2unix` or equivalent. |
| Mixed encodings within one file | Happens when CSVs are concatenated from multiple sources. `force_utf8: true` with `invalid_byte_sequence: ''` is the best available mitigation, but true mixed-encoding files cannot be reliably fixed by any parser. | Identify and re-encode each source file before concatenating. |
| Unquoted fields containing the column separator | Malformed CSV — the field will be split incorrectly and there is no way to recover the original value. | Fix upstream at the data source. |
| Repeated header row mid-file | Happens when files are assembled with `cat chunk_1.csv chunk_2.csv`. The repeated header lands as a data row: `{name: "name", age: "age"}`. | Strip repeated header lines before parsing, or post-filter rows where all values equal their key names. |
| Trailer / summary rows | Totals or citation rows at end of file have no consistent marker. | Pre-process to remove, or post-filter with a sentinel check: `rows.reject { \|r\| r[:date].nil? }`. |
| REDCap (clinical trial data) | Two-row header: field names row + field labels row. The labels row lands as the first data row. | Drop post-parse: `rows.drop(1)`, or pre-process to remove the labels row. |
| IRS / SOI Tax Stats — footnote rows mixed into data | Footnote rows (e.g. `* Data suppressed`) appear mid-file with no consistent column structure. No option to filter mid-file rows by pattern. | Pre-process to strip footnote lines before parsing. |
| UK ONS (Office for National Statistics) — multi-row headers | Title row + unit row before the actual header row. SmarterCSV reads one header row; the extra rows land as data. | Pre-process to collapse or remove the extra header rows. |
| UK ONS — footer footnotes (`[note]`, `[x]`) | Footnote rows at end of file use inline markers with no consistent structure. | Pre-process to strip footer lines, or post-filter rows where key fields are nil. |
| World Bank / IMF — footer with source citation | Last 1–3 lines contain source attribution text, not data. | Pre-process to strip, or use `rows[0..-N]` to drop the last N rows post-parse. |
| Australian ABS — merged cell artifacts | Excel merged cells export as a value in the first occurrence and blank in subsequent rows. The blank column becomes `:column_1` with empty values. | Post-process: forward-fill the blank column from the previous non-empty value. |

---

## Quick Reference: Common Option Combinations

```ruby
# Legacy enterprise export (Windows, Latin-1, BOM, CRLF)
SmarterCSV.process(file, file_encoding: 'windows-1252')

# MySQL dump (backslash escaping, \N for NULL)
SmarterCSV.process(file,
  quote_escaping: :backslash,
  nil_values_matching: /\A\\N\z/)

# Financial data (preserve leading zeros, no numeric conversion on key fields)
SmarterCSV.process(file,
  convert_values_to_numeric: { except: [:account_number, :zip, :routing_number] })

# SAP wide export with duplicate column names
SmarterCSV.process(file,
  duplicate_header_suffix: '_',
  strip_whitespace: true)

# Survey export with boolean and N/A values
SmarterCSV.process(file,
  nil_values_matching: /\A(N\/A|NA|n\/a)\z/,
  value_converters: {
    completed: ->(v) { v&.upcase == 'Y' }
  })

# Gzipped CSV
require 'zlib'
SmarterCSV.process(Zlib::GzipReader.open('data.csv.gz'))

# HTTP streaming
require 'open-uri'
SmarterCSV.process(URI.open('https://example.com/data.csv'))
```

--------------------
PREVIOUS: [Instrumentation Hooks](./instrumentation.md) | NEXT: [Examples](./examples.md) | UP: [README](../README.md)
