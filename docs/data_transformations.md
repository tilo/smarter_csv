# Data Transformations

SmarterCSV automatically transforms the values in each colum in order to normalize the data.
This behavior can be customized or disabled.

## Remove Empty Values
`remove_empty_values` is enabled by default
It removes any values which are `nil` or would be empty strings.

## Convert Values to Numeric
`convert_values_to_numeric` is enabled by default. 
SmarterCSV will convert strings containing Integers or Floats to the appropriate class.

## Remove Zero Values
`remove_zero_values` is disabled by default.
When enabled, it removes key/value pairs which have a numeric value equal to zero.

## Remove Values Matching
`remove_values_matching` is disabled by default. 
When enabled, this can help removing key/value pairs from result hashes which would cause problems. 

e.g.
 * `remove_values_matching: /^\$0\.0+$/` would remove $0.00 
 * `remove_values_matching: /^#VALUE!$/` would remove errors from Excel spreadsheets 

## Empty Hashes

It can happen that after all transformations, a row of the CSV file would produce a completely empty hash.

By default SmarterCSV uses `remove_empty_hashes: true` to remove these empty hashes from the result.

This can be set to `true`, to keep these empty hashes in the results.
