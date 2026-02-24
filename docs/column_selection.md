
### Contents

  * [Introduction](./_introduction.md)
  * [Parsing Strategy](./parsing_strategy.md)
  * [The Basic Read API](./basic_read_api.md)
  * [The Basic Write API](./basic_write_api.md)
  * [Batch Processing](././batch_processing.md)
  * [Configuration Options](./options.md)
  * [Row and Column Separators](./row_col_sep.md)
  * [Header Transformations](./header_transformations.md)
  * [Header Validations](./header_validations.md)
  * [**Column Selection**](./column_selection.md)
  * [Data Transformations](./data_transformations.md)
  * [Value Converters](./value_converters.md)
  * [Bad Row Quarantine](./bad_row_quarantine.md)
  * [Examples](./examples.md)
  * [SmarterCSV over the Years](./history.md)

--------------

# Column Selection

Wide CSV files often contain dozens or hundreds of columns, but a given application typically
only needs a handful of them. The `only_headers:` and `except_headers:` options let you declare
upfront which columns you want, so SmarterCSV skips allocation and hash insertion for everything
else — both in the Ruby path and in the C-accelerated hot path.

## Options

| Option | Default | Description |
|--------|---------|-------------|
| `only_headers:` | `nil` | Keep only the listed columns in each result hash |
| `except_headers:` | `nil` | Remove the listed columns from each result hash |

You cannot use both options at the same time — doing so raises `SmarterCSV::ValidationError`.

## Basic usage

```ruby
# Keep only two columns out of a wide file
data = SmarterCSV.process('big.csv', only_headers: [:id, :email])
# => [{id: 1, email: "alice@example.com"}, ...]

# Keep everything except one noisy column
data = SmarterCSV.process('big.csv', except_headers: [:internal_notes])
```

## Input flexibility

Both options accept an Array of symbols or strings, or a single symbol or string — anything
that makes sense as a column name. All values are normalized to symbols internally.

```ruby
only_headers: :id                     # single symbol — same as [:id]
only_headers: 'id'                    # single string — normalized to :id
only_headers: [:id, :email]           # array of symbols
only_headers: ['id', 'email']         # array of strings — normalized to symbols
```

## Names refer to post-mapping keys

`only_headers:` and `except_headers:` use the **post-mapping** column name — the symbol that
actually appears in the result hash after `key_mapping:` has been applied. You never need to
know the original CSV header spelling.

```ruby
# CSV has header "First Name"; key_mapping renames it to :given_name
data = SmarterCSV.process('contacts.csv',
  key_mapping:   { first_name: :given_name },
  only_headers:  [:given_name],            # post-mapping name
)
# => [{given_name: "Alice"}, ...]
```

## Interaction with `with_line_numbers:`

`:csv_line_number` is added to each hash **after** column selection runs, so it is always
present when `with_line_numbers: true` — even if it is not listed in `only_headers:`.

```ruby
data = SmarterCSV.process('data.csv',
  only_headers:     [:name],
  with_line_numbers: true,
)
data.each { |row| puts "#{row[:csv_line_number]}: #{row[:name]}" }
```

## Interaction with `strict:`

`strict: true` raises `SmarterCSV::HeaderSizeMismatch` when a data row contains more fields
than the header row. This check runs **before** column selection, so schema validation still
catches malformed rows even when `only_headers:` is active.

```ruby
# Raises HeaderSizeMismatch on the row with extra fields, regardless of only_headers:
SmarterCSV.process('data.csv', only_headers: [:name], strict: true)
```

## Extra columns without `strict:`

When `strict:` is false (the default) and a data row has more fields than the header,
the extra columns are silently dropped — they cannot be in the `only_headers:` set, so the
filter discards them naturally.

## Unknown column names are silently ignored

Listing a column name that doesn't exist in the file is not an error. The column simply
never appears in any row hash.

```ruby
# :nonexistent_column is not in the file — no error, just absent from results
data = SmarterCSV.process('data.csv', only_headers: [:id, :nonexistent_column])
```

## Performance

Both options are implemented in the C extension (when acceleration is enabled). Excluded
columns are skipped entirely inside the C parsing loop — no Ruby string is allocated, no
numeric conversion runs, and no `rb_hash_aset` call is made for fields the caller doesn't
need. This makes column selection a genuine performance option for wide CSV files, not just
a post-processing filter.

The Ruby fallback path applies the same filter via `hash.select!` / `hash.reject!` after
parsing, giving correct results on all platforms.

---

PREVIOUS: [Header Validations](./header_validations.md) | NEXT: [Data Transformations](./data_transformations.md)
