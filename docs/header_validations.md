
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
  * [**Header Validations**](./header_validations.md)
  * [Column Selection](./column_selection.md)
  * [Data Transformations](./data_transformations.md)
  * [Value Converters](./value_converters.md)
  * [Bad Row Quarantine](./bad_row_quarantine.md)
  * [Instrumentation Hooks](./instrumentation.md)
  * [Examples](./examples.md)
  * [Real-World CSV Files](./real_world_csv.md)
  * [SmarterCSV over the Years](./history.md)
  * [Release Notes](./releases/1.16.0/changes.md)

--------------

# Header Validations

When importing data it is important to verify that all required columns are present — catching a missing column upfront is far better than a cryptic error later when your code tries to access a key that was never populated.

## `required_keys`

Use `required_keys` to specify an array of hash keys that must be present after header transformation. Validation runs once, after the header row is parsed and all header transformations (downcase, symbolize, `key_mapping`) have been applied — so use the **transformed** key names, not the raw CSV header strings.

If any required key is absent, `SmarterCSV::MissingKeys` is raised before any data rows are processed.

```ruby
options = {
  required_keys: [:source_account, :destination_account, :amount]
}
data = SmarterCSV.process('/tmp/transactions.csv', options)
# => raises SmarterCSV::MissingKeys if any of the three columns are missing
```

### Accessing the missing keys

`SmarterCSV::MissingKeys` exposes the missing keys via the `keys` accessor:

```ruby
begin
  data = SmarterCSV.process('/tmp/transactions.csv',
    required_keys: [:source_account, :destination_account, :amount])
rescue SmarterCSV::MissingKeys => e
  puts "Missing columns: #{e.keys.join(', ')}"
  # => "Missing columns: amount"
end
```

### Interaction with `key_mapping`

`required_keys` uses the **post-mapping** key names. If you remap CSV headers, reference the mapped names:

```ruby
options = {
  key_mapping:   { acct_from: :source_account, acct_to: :destination_account },
  required_keys: [:source_account, :destination_account, :amount],
}
```

---

## `silence_missing_keys`

When using `key_mapping`, SmarterCSV raises `SmarterCSV::KeyMappingError` if a mapped key is not found in the CSV header. Use `silence_missing_keys` to make some or all mapped keys optional:

```ruby
# All mapped keys are optional — no error if any are absent
options = {
  key_mapping:          { optional_field: :my_field, required_field: :other_field },
  silence_missing_keys: true,
}

# Only specific mapped keys are optional
options = {
  key_mapping:          { optional_field: :my_field, required_field: :other_field },
  silence_missing_keys: [:optional_field],
}
```

----------------
PREVIOUS: [Header Transformations](./header_transformations.md) | NEXT: [Column Selection](./column_selection.md) | UP: [README](../README.md)
