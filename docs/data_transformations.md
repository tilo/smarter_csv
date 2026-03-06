
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
  * [**Data Transformations**](./data_transformations.md)
  * [Value Converters](./value_converters.md)
  * [Bad Row Quarantine](./bad_row_quarantine.md)
  * [Instrumentation Hooks](./instrumentation.md)
  * [Examples](./examples.md)
  * [SmarterCSV over the Years](./history.md)

--------------

# Data Transformations

SmarterCSV automatically transforms the values in each colum in order to normalize the data.
This behavior can be customized or disabled.

## Remove Empty Values
`remove_empty_values` is enabled by default
It removes any values which are `nil` or would be empty strings.

## Convert Values to Numeric
`convert_values_to_numeric` is enabled by default. 
SmarterCSV will convert strings containing Integers or Floats to the appropriate class.

Here is an example of using `convert_values_to_numeric` for numbers with leading zeros, e.g. ZIP codes:

```
  data = SmarterCSV.process('/tmp/zip.csv',  convert_values_to_numeric: { except: [:zip] })
   => [{:zip=>"00480"}, {:zip=>"51903"}, {:zip=>"12354"}, {:zip=>"02343"}]
```   

This will return the column `:zip` as a string with all digits intact.

## Remove Zero Values
`remove_zero_values` is disabled by default.
When enabled, it removes key/value pairs which have a numeric value equal to zero.

## Nil Values Matching
`nil_values_matching` is disabled by default.
When enabled, values matching the given regular expression are set to `nil`. With the default
`remove_empty_values: true`, those key/value pairs are then removed. With `remove_empty_values: false`,
the key is retained with a `nil` value — useful when you need to distinguish "field was absent"
from "field had a sentinel value".

e.g.
 * `nil_values_matching: /^\$0\.0+$/` would nil-ify (and by default remove) $0.00
 * `nil_values_matching: /^(NaN|#VALUE!)$/` would nil-ify NaN and Excel errors

> **Deprecated:** `remove_values_matching:` still works but emits a deprecation warning.
> Use `nil_values_matching:` instead.

## Empty Hashes

It can happen that after all transformations, a row of the CSV file would produce a completely empty hash.

By default SmarterCSV uses `remove_empty_hashes: true` to remove these empty hashes from the result.

This can be set to `false`, to keep these empty hashes in the results.

-------------------
PREVIOUS: [Column Selection](./column_selection.md) | NEXT: [Value Converters](./value_converters.md)
