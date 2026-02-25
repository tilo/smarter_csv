
### Contents

  * [Introduction](./_introduction.md)
  * [Migrating from Ruby CSV](./migrating_from_csv.md)
  * [Parsing Strategy](./parsing_strategy.md)
  * [The Basic Read API](./basic_read_api.md)
  * [The Basic Write API](./basic_write_api.md)
  * [Batch Processing](././batch_processing.md)
  * [**Configuration Options**](./options.md)
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

# Configuration Options

## CSV Writing

| Option | Default | Explanation |
|--------|---------|-------------|
| `:row_sep` | `$/` | Separates rows. Defaults to your OS row separator: `\n` on UNIX, `\r\n` on Windows. |
| `:col_sep` | `","` | Separates each value in a row. |
| `:quote_char` | `'"'` | Character used to quote CSV fields. |
| `:force_quotes` | `false` | Forces each individual value to be quoted. |
| `:headers` | `[]` | List of keys from the input to use as headers in the CSV file. ⚠️ Disables automatic header detection! |
| `:map_headers` | `{}` | Like `:headers`, but also maps each key to a user-specified header value. ⚠️ Disables automatic header detection! |
| `:value_converters` | `nil` | Lambdas to programmatically modify values — either for specific key names, or using `_all` for all fields. |
| `:header_converter` | `nil` | One lambda to programmatically modify the headers. |
| `:discover_headers` | `true` | Automatically detects all keys in the input before writing the header. Do not set to `false` manually. ⚠️ |
| `:disable_auto_quoting` | `false` | Manually disables auto-quoting of special characters. ⚠️ Use with care! |
| `:quote_headers` | `false` | Force quoting all headers (only needed in rare cases). |


## CSV Reading

### File Input & Encoding

| Option | Default | Explanation |
|--------|---------|-------------|
| `:file_encoding` | `utf-8` | Set the file encoding, e.g. `'windows-1252'` or `'iso-8859-1'`. |
| `:invalid_byte_sequence` | `''` | What to replace invalid byte sequences with. |
| `:force_utf8` | `false` | Force UTF-8 encoding of all lines (including headers) in the CSV file. |

### File Layout

| Option | Default | Explanation |
|--------|---------|-------------|
| `:skip_lines` | `nil` | How many lines to skip before the first line or header line is processed. |
| `:comment_regexp` | `nil` | Regular expression to ignore comment lines (e.g. `/\A#/`). See NOTE on CSV header. |
| `:chunk_size` | `nil` | If set, data is yielded in chunks of this many rows instead of all at once. Use with `SmarterCSV.each_chunk` for memory-efficient batch processing. |

### Separators

| Option | Default | Explanation |
|--------|---------|-------------|
| `:col_sep` | `:auto` | Column separator. `:auto` detects from file content (previous default was `','`). |
| `:row_sep` | `:auto` | Row / record separator. `:auto` detects from file content. Manual detection reads the whole file first (slow on large files). |
| `:auto_row_sep_chars` | `500` | How many characters to analyze when using `:row_sep => :auto`. `nil` or `0` means whole file. |

### Quoting

See [Parsing Strategy](./parsing_strategy.md) for full details on quote handling.

| Option | Default | Explanation |
|--------|---------|-------------|
| `:quote_char` | `'"'` | Quotation character. Must be a single byte. |
| `:quote_escaping` | `:auto` | How quotes are escaped inside quoted fields. `:auto` (default): tries backslash-escape first, falls back to RFC 4180. `:double_quotes` (RFC 4180): only `""` escapes a quote; backslash is literal. `:backslash` (MySQL/Unix): `\"` also escapes a quote. |
| `:quote_boundary` | `:standard` | Where quote characters are recognized as field delimiters. `:standard` (default): a quote only opens a field at a field boundary (first character of the field); mid-field quotes are literal. `:legacy`: any quote toggles quoted state regardless of position (old behavior). |

### Headers

| Option | Default | Explanation |
|--------|---------|-------------|
| `:headers_in_file` | `true` ¹ | Whether the file contains headers as the first line. ¹ If `user_provided_headers` is given, default becomes `false` unless explicitly set to `true`. |
| `:user_provided_headers` | `nil` | *Careful!* User-provided Array of header strings or symbols, overriding any in-file headers. Cannot be combined with `:key_mapping`. |
| `:duplicate_header_suffix` | `''` | Appends a number to duplicated headers, separated by this suffix. Set to `nil` to raise `DuplicateHeaders` error instead (previous behavior). |
| `:downcase_header` | `true` | Downcase all column headers. |
| `:strings_as_keys` | `false` | Use strings instead of symbols as keys in the result hashes. |
| `:keep_original_headers` | `false` | Keep the original headers from the CSV file as-is. Disables other flags that manipulate header fields. |
| `:strip_chars_from_headers` | `nil` | RegExp to remove extraneous characters from the header line (e.g. if headers are quoted). |
| `:missing_header_prefix` | `column_` | Prefix for auto-generated column names when extra columns are found. |
| `:missing_headers` | `:auto` | Behavior when a data row has more columns than the header row. `:auto` (default): auto-name extra columns using `missing_header_prefix`. `:raise`: raise `HeaderSizeMismatch` on the first row with extra columns. |

### Header Mapping & Validation

| Option | Default | Explanation |
|--------|---------|-------------|
| `:key_mapping` | `nil` | A hash mapping CSV headers to keys in the result hash. |
| `:silence_missing_keys` | `false` | Ignore missing keys in `key_mapping`. `true` makes all mapped keys optional; an Array makes only the listed keys optional. |
| `:remove_unmapped_keys` | `false` | When using `key_mapping`, remove columns that have no mapping. |
| `:required_keys` | `nil` | Array of key names (after header transformation) that must be present. Raises an exception if any required key is missing. No validation if `nil`. |

### Column Selection

| Option | Default | Explanation |
|--------|---------|-------------|
| `headers: { only: }` | `nil` | Keep only the listed columns in each result hash. See [Column Selection](./column_selection.md). Accepts a symbol, string, or array of either (normalized to symbols). Uses post-mapping names (after `key_mapping:` is applied). Cannot be combined with `headers: { except: }`. |
| `headers: { except: }` | `nil` | Remove the listed columns from each result hash. See [Column Selection](./column_selection.md). Accepts a symbol, string, or array of either (normalized to symbols). Uses post-mapping names (after `key_mapping:` is applied). Cannot be combined with `headers: { only: }`. |

### Value Transformations

| Option | Default | Explanation |
|--------|---------|-------------|
| `:strip_whitespace` | `true` | Remove whitespace before/after values and headers. |
| `:convert_values_to_numeric` | `true` | Convert strings containing integers or floats to the appropriate numeric type. Accepts `{except: [:key1, :key2]}` or `{only: :key3}` to limit which columns. |
| `:value_converters` | `nil` | Hash of `:header => ClassName`; each class must implement `self.convert(value)`. See [Value Converters](./value_converters.md). |
| `:remove_empty_values` | `true` | Remove key/value pairs where the value is `nil` or an empty string. |
| `:remove_zero_values` | `false` | Remove key/value pairs where the numeric value equals zero. |
| `:nil_values_matching` | `nil` | Set matching values to `nil`. Accepts a regular expression matched against the string representation of each value (e.g. `/\ANAN\z/` for NaN, `/\A#VALUE!\z/` for Excel errors). With `remove_empty_values: true` (default), nil-ified values are then removed. With `remove_empty_values: false`, the key is retained with a `nil` value. |
| `:remove_empty_hashes` | `true` | Remove result hashes that have no key/value pairs or all-empty values. |

### Error Handling

See [Bad Row Quarantine](./bad_row_quarantine.md) for full details.

| Option | Default | Explanation |
|--------|---------|-------------|
| `:on_bad_row` | `:raise` | Behavior when a row raises a parse error. `:raise` (default): re-raise, stopping processing. `:skip`: skip the bad row and continue. `:collect`: skip and append an error record to `reader.errors[:bad_rows]`. callable: called with the error record per bad row; processing continues. |
| `:collect_raw_lines` | `true` | When collecting bad rows, include the raw stitched line in the error record. |
| `:bad_row_limit` | `nil` | If set, raises `SmarterCSV::TooManyBadRows` after this many bad rows. |

### Output & Diagnostics

| Option | Default | Explanation |
|--------|---------|-------------|
| `:with_line_numbers` | `false` | Add `:csv_line_number` to each result hash. |
| `:verbose` | `:normal` | Controls warning and diagnostic output. Accepted values:<br>• `:quiet` — suppress all warnings and notices (recommended for production)<br>• `:normal` — show behavioral warnings, e.g. auto-configuration notices **(default)**<br>• `:debug` — `:normal` + print computed options and per-row diagnostics to stderr<br>`nil` is silently treated as `:normal`. Passing `true` or `false` still works but is deprecated — see below. |

### Performance

| Option | Default | Explanation |
|--------|---------|-------------|
| `:acceleration` | `true` | Use the C extension for parsing (MRI Ruby only). Set to `false` to force the pure-Ruby fallback (always used on JRuby/TruffleRuby). |

---

## Deprecated Options

These options are still accepted but emit a deprecation warning. They will be removed in a future version.

| Option | Default | Replacement |
|--------|---------|-------------|
| `:strict` | `false` | Use `missing_headers: :raise` instead of `strict: true`, or `missing_headers: :auto` instead of `strict: false`. |
| `:required_headers` | `nil` | Renamed to `:required_keys`. Use `required_keys:` instead. |
| `:remove_values_matching` | `nil` | Renamed to `:nil_values_matching`. Use `nil_values_matching:` instead. |
| `verbose: true` | — | Use `verbose: :debug` instead. |
| `verbose: false` | — | Use `verbose: :normal` (or omit — it is the default) instead. |

-------------
PREVIOUS: [Batch Processing](./batch_processing.md) | NEXT: [Row and Column Separators](./row_col_sep.md)
