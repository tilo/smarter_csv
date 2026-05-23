
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
  * [**Header Transformations**](./header_transformations.md)
  * [Header Validations](./header_validations.md)
  * [Column Selection](./column_selection.md)
  * [Data Transformations](./data_transformations.md)
  * [Value Converters](./value_converters.md)
  * [Bad Row Quarantine](./bad_row_quarantine.md)
  * [Warnings](./warnings.md)
  * [Instrumentation Hooks](./instrumentation.md)
  * [Examples](./examples.md)
  * [Real-World CSV Files](./real_world_csv.md)
  * [SmarterCSV over the Years](./history.md)
  * [Release Notes](./releases/1.18.0/changes.md)

--------------

# Header Transformations

By default SmarterCSV assumes that a CSV file has headers, and it automatically normalizes the headers and transforms them into Ruby symbols. You can completely customize or override this (see below).

## Header Transformation Pipeline

When a CSV file is opened, the header line passes through the following steps in order:

```
[user_provided_headers] ──► skips steps below; uses your array directly
         │
         ▼ (when headers come from the file)
comment_regexp ──► strip_chars_from_headers ──► split on col_sep
    ──► strip quote_char ──► strip_whitespace
    ──► [unless keep_original_headers]: gsub spaces/dashes→_ ──► downcase_header
    ──► disambiguate_headers ──► symbolize ──► key_mapping
```

| Step | Option | Default | Description |
|------|--------|---------|-------------|
| 1 | `comment_regexp` | `nil` | Strips a comment prefix from the raw header line (e.g. `# ` at start) |
| 2 | `strip_chars_from_headers` | `nil` | Removes characters matching a regexp from the raw header line (e.g. `/[\-"]/`) |
| 3 | *(split)* | `col_sep` | Splits the header line into individual column tokens |
| 4 | `quote_char` | `"` | Strips surrounding quote characters from each token |
| 5 | `strip_whitespace` | `true` | Strips leading/trailing whitespace from each header |
| 6 | *(normalize)* | — | Replaces spaces and dashes with `_` (`keep_original_headers` skips this and steps 7–9) |
| 7 | `downcase_header` | `true` | Downcases each header string |
| 8 | `duplicate_header_suffix` | `''` | Renames empty headers to `column_N`; appends suffix+number to duplicates |
| 9 | `strings_as_keys` | `false` | Converts headers to symbols (skipped if `true` or `keep_original_headers`) |
| 10 | `key_mapping` | `nil` | Renames or drops headers; use post-transformation key names as input |

> `user_provided_headers` bypasses all file header reading and transformation entirely — your array is used as-is. Versions >1.13 automatically set `headers_in_file: false` when `user_provided_headers` is given; if the file has a header row you want to skip, set `headers_in_file: true` explicitly.

See [Configuration Options](./options.md) for full option reference.

---

## CSV Files with Comment Lines

Strip comment lines anywhere in the file — including before the header — using `comment_regexp`:

```ruby
$ cat data.csv
# Generated 2026-01-15 by exporter v3.2
# Confidential — internal use only
id,name,amount
1,Alice,100
2,Bob,200
# end of file

data = SmarterCSV.process('data.csv', comment_regexp: /\A#/)
# => [{id: 1, name: "Alice", amount: 100},
#     {id: 2, name: "Bob",   amount: 200}]
```

Common in database dumps, log exports, and pipelines that prepend provenance metadata. The regexp is applied per line — any line matching is dropped before parsing.

---

## Header Normalization

When processing the headers, it transforms them into Ruby symbols, stripping extra spaces, lower-casing them and replacing spaces with underscores. e.g. " \t Annual Sales  " becomes `:annual_sales`. (see Notes below)

## Duplicate Headers

There can be a lot of variation in CSV files. It is possible that a CSV file contains multiple headers with the same name. 

By default SmarterCSV handles duplicate headers by appending numbers 2..n to them.

Consider this example:

```
$ cat > /tmp/dupe.csv
name,name,name
Carl,Edward,Sagan
```

When parsing these duplicate headers, SmarterCSV will return:

```
  data = SmarterCSV.process('/tmp/dupe.csv')
   => [{:name=>"Carl", :name2=>"Edward", :name3=>"Sagan"}]
```

If you want to have an underscore between the header and the number, you can set `duplicate_header_suffix: '_'`.

```
  data = SmarterCSV.process('/tmp/dupe.csv', {duplicate_header_suffix: '_'})
   => [{:name=>"Carl", :name_2=>"Edward", :name_3=>"Sagan"}]
```
 
 To further disambiguate the headers, you can further use `key_mapping` to assign meaningful names. Please note that the mapping uses the already transformed keys `name_2`, `name_3` as input.
   
```
  options = {
    duplicate_header_suffix: '_', 
    key_mapping: {
      name: :first_name, 
      name_2: :middle_name, 
      name_3: :last_name,
    }
  }
  data = SmarterCSV.process('/tmp/dupe.csv', options)
   => [{:first_name=>"Carl", :middle_name=>"Edward", :last_name=>"Sagan"}]
```

If you set `duplicate_header_suffix: nil`, you get the same behavior as earlier versions, which raised the `SmarterCSV::DuplicateHeaders` error.

When `SmarterCSV::DuplicateHeaders` is raised, you can access the duplicate headers directly via the `headers` accessor:

```ruby
begin
  data = SmarterCSV.process('/tmp/dupe.csv', {duplicate_header_suffix: nil})
rescue SmarterCSV::DuplicateHeaders => e
  puts "Duplicate columns: #{e.headers.join(', ')}"
  # => e.headers returns [:name] (array of duplicate header symbols)
end
```

## Key Mapping

`key_mapping:` renames CSV headers to the symbols your application expects. Any header not
listed in the mapping is kept as-is by default.

```ruby
# CSV headers: first_name, last_name, internal_id, created_at
data = SmarterCSV.process('contacts.csv',
  key_mapping: { first_name: :given_name, last_name: :family_name },
)
# => [{given_name: "Alice", family_name: "Smith", internal_id: 42, created_at: "2026-01-01"}, ...]
#       ^^^ renamed                                ^^^ unmapped keys kept as-is
```

To delete a specific column, map it to `nil` — it will be removed from every row hash:

```ruby
key_mapping: { internal_id: nil, created_at: nil }   # drop these two columns
```

### `remove_unmapped_keys:` — drop everything not in the map

When you have files with many columns and only care about a few, listing every unwanted
column as `nil` is tedious. Use `remove_unmapped_keys: true` to implicitly drop any header
that has no entry in `key_mapping:`:

```ruby
# CSV has 50 columns; you only want two of them, renamed
data = SmarterCSV.process('contacts.csv',
  key_mapping:          { first_name: :given_name, last_name: :family_name },
  remove_unmapped_keys: true,
)
# => [{given_name: "Alice", family_name: "Smith"}, ...]   # only the two mapped columns
```

### `remove_unmapped_keys:` vs `headers: { only: }`

Both achieve column selection, but they serve different purposes:

| | `remove_unmapped_keys: true` | `headers: { only: [...] }` |
|---|---|---|
| Use when | Already using `key_mapping:` and want to implicitly drop the rest | Pure column selection, no renaming needed |
| Performance | Post-parse filter — all fields parsed, unmapped keys deleted | **C-path early exit** — unneeded fields never parsed |
| Renaming | Yes — combines selection and rename in one step | No renaming (use `key_mapping:` alongside if needed) |

For wide files where performance matters, prefer `headers: { only: }` — it skips unneeded
fields entirely inside the C parser and can be **10–14× faster** on very wide files.
Use `remove_unmapped_keys: true` when you are already remapping headers and the convenience
of a single option outweighs the (usually small) performance difference.

See [Column Selection](./column_selection.md) for full details on `headers: { only: }`.

> **Note:** Key mapping is particularly useful when importing CSV data directly into a database or document store. By remapping headers to the exact symbol names your application uses internally (e.g. ActiveRecord attributes, DynamoDB document keys, Sidekiq job parameters), you can pass the resulting hashes directly without any further transformation.

## CSV Files without Headers

If you have CSV files without headers, it is important to set `headers_in_file: false`, otherwise you'll lose the first data line in your file. 
You then have to provide `user_provided_headers`, which takes an array of either symbols or strings. Versions >1.13 now automatically set `headers_in_file: false` if you provide `user_provided_headers`. Also see next paragraph.


## CSV Files with Headers

For CSV files with headers, you can either:

* use the automatic header normalization
* map one or more headers into whatever you chose using the `map_headers` option.
  (if you map a header to `nil`, it will remove that column from the resulting row hash).
* completely replace the headers using `user_provided_headers` (please be careful with this powerful option, as it is not robust against changes in input format).
  When you use `user_provided_headers`, versions >1.13 will set `headers_in_file: false` -- so if you replace the headers for a file that has headers, you must set `headers_in_file: true` to override this and ignore the header row.
* use the original unmodified headers from the CSV file, using `keep_original_headers`. This results in hash keys that are strings, and may be padded with spaces.


# Notes

### NOTES about CSV Headers:
 * as this method parses CSV files, it is assumed that the first line of any file will contain a valid header
 * the first line with the header might be commented out, in which case you will need to set `comment_regexp: /\A#/`
 * any occurences of :comment_regexp or :row_sep will be stripped from the first line with the CSV header
 * any of the keys in the header line will be downcased, spaces replaced by underscore, and converted to Ruby symbols before being used as keys in the returned Hashes
 * you can not combine the :user_provided_headers and :key_mapping options
 * if the incorrect number of headers are provided via :user_provided_headers, versions >1.13 will automatically add column names `column_N` for additional unexpected columns. If you want to raise an error instead, add option `strict: true`, and it will raise `SmarterCSV::HeaderSizeMismatch`.

### NOTES on improper quotation and unwanted characters in headers:
 * some CSV files use un-escaped quotation characters inside fields. This can cause the import to break. To get around this, set the `quote_char` to something different, e.g. `quote_char: "%"`, or try setting `:strip_chars_from_headers => /[\-"]/` 

---------------
PREVIOUS: [Row and Column Separators](./row_col_sep.md) | NEXT: [Header Validations](./header_validations.md) | UP: [README](../README.md)
