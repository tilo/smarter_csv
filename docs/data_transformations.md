
### Contents

  * [Introduction](./_introduction.md)
  * [Migrating from Ruby CSV](./migrating_from_csv.md)
  * [Ruby CSV Pitfalls](./ruby_csv_pitfalls.md)
  * [Parsing Strategy](./parsing_strategy.md)
  * [The Basic Read API](./basic_read_api.md)
  * [The Basic Write API](./basic_write_api.md)
  * [Batch Processing](././batch_processing.md)
  * [Configuration Options](./options.md)
  * [Row and Column Separators](./row_col_sep.md)
  * [Header Transformations](./header_transformations.md)
  * [Header Validations](./header_validations.md)
  * [Column Selection](./column_selection.md)
  * [**Data Transformations**](./data_transformations.md)
  * [Value Converters](./value_converters.md)
  * [Bad Row Quarantine](./bad_row_quarantine.md)
  * [Warnings](./warnings.md)
  * [Instrumentation Hooks](./instrumentation.md)
  * [Examples](./examples.md)
  * [Real-World CSV Files](./real_world_csv.md)
  * [SmarterCSV over the Years](./history.md)
  * [Release Notes](./releases/1.16.0/changes.md)

--------------

# Data Transformations

SmarterCSV automatically normalizes the values in each row. All transformations are configurable — most are enabled by default because they're the right behavior for the vast majority of CSV files.

## Transformation Pipeline

Transformations run in this order for every row:

| Step | Option | Default | What it does |
|------|--------|---------|--------------|
| 1 | `strip_whitespace` | `true` | Strips leading/trailing whitespace from all values (and headers) at parse time |
| 2 | `nil_values_matching` | `nil` | Sets values matching the regexp to `nil` |
| 3 | `remove_empty_values` | `true` | Removes keys whose value is `nil` or blank |
| 4 | `remove_zero_values` | `false` | Removes keys whose value is numeric zero |
| 5 | `convert_values_to_numeric` | `true` | Converts numeric-looking strings to `Integer` or `Float` |
| 6 | `value_converters` | `nil` | Applies per-key custom converter lambdas or classes |
| 7 | `remove_empty_hashes` | `true` | Drops rows that are entirely empty after all transformations |

> Steps 2–6 run per field in order. `value_converters` receive the value **after** numeric conversion — guard against receiving `Integer`/`Float` if your converter expects a string.

---

## `strip_whitespace`

**Default: `true`**

Strips leading and trailing whitespace from all header names and all field values at parse time, before any other transformation runs.

```ruby
# CSV with padded values:
# name,  score
# Alice ,  42
# Bob   ,  0

data = SmarterCSV.process(file)
# => [{name: "Alice", score: 42}, {name: "Bob", score: 0}]
#  ↑ "Alice " stripped to "Alice", "  42" stripped to "42" then converted

data = SmarterCSV.process(file, strip_whitespace: false)
# => [{"name"=>"Alice ", " score"=>"  42"}, ...]
#  ↑ whitespace preserved in both headers and values
```

---

## `nil_values_matching`

**Default: `nil` (disabled)**

Set values matching the given regular expression to `nil`. Combined with the default `remove_empty_values: true`, matching values are removed from the result hash. With `remove_empty_values: false`, the key is retained with a `nil` value — useful when you need to distinguish "field was absent" from "field had a sentinel value".

```ruby
# Treat common null sentinels as nil and remove them
data = SmarterCSV.process(file, nil_values_matching: /\A(NULL|N\/A|NA|#N\/A|\(null\))\z/i)

# Nil-ify but retain the key (don't remove)
data = SmarterCSV.process(file,
  nil_values_matching: /\A(NULL|N\/A)\z/i,
  remove_empty_values: false)
# => [{name: "Alice", score: nil}]  ← key retained with nil value

# Remove Excel error values
data = SmarterCSV.process(file, nil_values_matching: /\A(#VALUE!|#REF!|#DIV\/0!|NaN)\z/)
```

> **Deprecated:** `remove_values_matching:` still works but emits a deprecation warning.
> Use `nil_values_matching:` instead.

---

## `remove_empty_values`

**Default: `true`**

Removes key/value pairs where the value is `nil` or an empty string after `strip_whitespace` and `nil_values_matching` have run. This is why SmarterCSV result hashes only contain keys with actual values — sparse CSV rows don't produce hashes cluttered with `nil` entries.

```ruby
# CSV: name,score,notes
#      Alice,42,
#      Bob,,great player

data = SmarterCSV.process(file)
# => [{name: "Alice", score: 42}, {name: "Bob", notes: "great player"}]
#  ↑ empty :notes and :score keys are dropped automatically

data = SmarterCSV.process(file, remove_empty_values: false)
# => [{name: "Alice", score: 42, notes: nil}, {name: nil, score: nil, notes: "great player"}]
```

---

## `remove_zero_values`

**Default: `false`**

When enabled, removes key/value pairs where the value is numeric zero (`0`, `0.0`, `"0"`, `"0.0"`). Useful when zero and absent mean the same thing in your domain.

```ruby
# CSV: product,quantity,discount
#      Widget,10,0
#      Gadget,0,5

data = SmarterCSV.process(file, remove_zero_values: true)
# => [{product: "Widget", quantity: 10}, {product: "Gadget", discount: 5}]
#  ↑ :discount=>0 and :quantity=>0 removed
```

---

## `convert_values_to_numeric`

**Default: `true`**

Converts string values that look like integers or floats to the appropriate numeric type. This is one of the most common sources of silent data loss if not configured carefully — fields like ZIP codes, phone numbers, and account numbers with leading zeros will be silently corrupted if not excluded.

```ruby
data = SmarterCSV.process(file)
# "42"     => 42    (Integer)
# "3.14"   => 3.14  (Float)
# "01234"  => 1234  ← leading zero lost! exclude this column

# Exclude specific columns from numeric conversion
data = SmarterCSV.process(file,
  convert_values_to_numeric: { except: [:zip, :phone, :account_number] })
# => [{zip: "01234", phone: "800-555-0100", amount: 99.99}]

# Only convert specific columns (all others stay as strings)
data = SmarterCSV.process(file,
  convert_values_to_numeric: { only: [:quantity, :price] })
```

---

## `remove_empty_hashes`

**Default: `true`**

After all per-field transformations, removes rows that have no remaining key/value pairs. This handles blank lines and rows where every field was empty or matched `nil_values_matching`.

```ruby
# CSV with a blank line between records:
# name,score
# Alice,42
#
# Bob,99

data = SmarterCSV.process(file)
# => [{name: "Alice", score: 42}, {name: "Bob", score: 99}]
#  ↑ blank line silently dropped

data = SmarterCSV.process(file, remove_empty_hashes: false)
# => [{name: "Alice", score: 42}, {}, {name: "Bob", score: 99}]
```

---

## Custom Transformations — `value_converters`

For type conversions beyond numeric (dates, booleans, currency, etc.), use `value_converters`. They run last in the pipeline, after numeric conversion. See [Value Converters](./value_converters.md) for full documentation.

```ruby
data = SmarterCSV.process(file, value_converters: {
  date:   ->(v) { v ? Date.strptime(v, '%m/%d/%Y') : nil },
  active: ->(v) { v&.match?(/\Atrue\z/i) },
})
```

-------------------
PREVIOUS: [Column Selection](./column_selection.md) | NEXT: [Value Converters](./value_converters.md) | UP: [README](../README.md)
