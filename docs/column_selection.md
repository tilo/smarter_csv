
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
  * [**Column Selection**](./column_selection.md)
  * [Data Transformations](./data_transformations.md)
  * [Value Converters](./value_converters.md)
  * [Bad Row Quarantine](./bad_row_quarantine.md)
  * [Examples](./examples.md)
  * [SmarterCSV over the Years](./history.md)

--------------

# Column Selection

Wide CSV files often contain dozens or hundreds of columns, but a given application typically
only needs a handful of them. The `headers: { only: }` and `headers: { except: }` options let
you declare upfront which columns you want, so SmarterCSV skips allocation and hash insertion
for everything else — both in the Ruby path and in the C-accelerated hot path.

## Options

| Option | Default | Description |
|--------|---------|-------------|
| `headers: { only: }` | `nil` | Keep only the listed columns in each result hash |
| `headers: { except: }` | `nil` | Remove the listed columns from each result hash |

You cannot use both options at the same time — doing so raises `SmarterCSV::ValidationError`.

## Basic usage

```ruby
# Keep only two columns out of a wide file
data = SmarterCSV.process('big.csv', headers: { only: [:id, :email] })
# => [{id: 1, email: "alice@example.com"}, ...]

# Keep everything except one noisy column
data = SmarterCSV.process('big.csv', headers: { except: [:internal_notes] })
```

## Input flexibility

Both options accept an Array of symbols or strings, or a single symbol or string — anything
that makes sense as a column name. All values are normalized to symbols internally.

```ruby
headers: { only: :id }                     # single symbol — same as [:id]
headers: { only: 'id' }                    # single string — normalized to :id
headers: { only: [:id, :email] }           # array of symbols
headers: { only: ['id', 'email'] }         # array of strings — normalized to symbols
```

## Names refer to post-mapping keys

`headers: { only: }` and `headers: { except: }` use the **post-mapping** column name — the
symbol that actually appears in the result hash after `key_mapping:` has been applied. You
never need to know the original CSV header spelling.

```ruby
# CSV has header "First Name"; key_mapping renames it to :given_name
data = SmarterCSV.process('contacts.csv',
  key_mapping:  { first_name: :given_name },
  headers:      { only: [:given_name] },   # post-mapping name
)
# => [{given_name: "Alice"}, ...]
```

## Interaction with `with_line_numbers:`

`:csv_line_number` is added to each hash **after** column selection runs, so it is always
present when `with_line_numbers: true` — even if it is not listed in `headers: { only: }`.

```ruby
data = SmarterCSV.process('data.csv',
  headers:           { only: [:name] },
  with_line_numbers: true,
)
data.each { |row| puts "#{row[:csv_line_number]}: #{row[:name]}" }
```

## Interaction with `strict:`

`strict: true` raises `SmarterCSV::HeaderSizeMismatch` when a data row contains more fields
than the header row. This check runs **before** column selection, so schema validation still
catches malformed rows even when `headers: { only: }` is active.

```ruby
# Raises HeaderSizeMismatch on the row with extra fields, regardless of headers: { only: }
SmarterCSV.process('data.csv', headers: { only: [:name] }, strict: true)
```

## Extra columns without `strict:`

When `strict:` is false (the default) and a data row has more fields than the header,
the extra columns are silently dropped — they cannot be in the `headers: { only: }` set, so
the filter discards them naturally.

> **Important:** `missing_headers: :auto` (auto-generating names like `column_7`,
> `column_8` for extra data columns) does **not** work in combination with `headers: { only: }`.
> `headers: { only: }` is a **performance improvement** that causes the parser to stop scanning
> a row once all requested columns have been found — any extra columns beyond the header
> count are never visited, so no auto-names are generated for them. If you need to capture
> auto-named overflow columns, do not use `headers: { only: }` at the same time.

## Unknown column names are silently ignored

Listing a column name that doesn't exist in the file is not an error. The column simply
never appears in any row hash.

```ruby
# :nonexistent_column is not in the file — no error, just absent from results
data = SmarterCSV.process('data.csv', headers: { only: [:id, :nonexistent_column] })
```

## Performance

Both options are implemented in the C extension (when acceleration is enabled). Excluded
columns are skipped entirely inside the C parsing loop — no Ruby string is allocated, no
numeric conversion runs, and no `rb_hash_aset` call is made for fields the caller doesn't
need. This makes column selection a genuine performance option for wide CSV files, not just
a post-processing filter.

The Ruby fallback path applies the same filter via `hash.select!` / `hash.reject!` after
parsing, giving correct results on all platforms.

### `headers: { only: }` vs `headers: { except: }` — performance asymmetry

**`headers: { only: }` enables early exit.** Once every requested column has been parsed,
the parser stops scanning the current row entirely — the remaining fields are never visited.
For a 500-column file where you only need 5 columns near the start, this can be
**10–14× faster** than parsing all columns.

**`headers: { except: }` cannot have early exit.** To know which columns to *keep*, the
parser must scan every field in the row to the end. Skipping just a few columns out of many
saves very little work, so benchmark results for `headers: { except: }` are typically flat
(0.7×–1.0× vs full parse).

**Rule of thumb:**
- Use `headers: { only: }` when you want a small subset of a wide file — this is the fast path.
- Use `headers: { except: }` only when you want *almost everything* and excluding a known
  noisy column is more convenient than listing all the ones you want.
- Avoid `headers: { except: }` as a performance tool on wide files — it provides no speed benefit.

---

PREVIOUS: [Header Validations](./header_validations.md) | NEXT: [Data Transformations](./data_transformations.md)
