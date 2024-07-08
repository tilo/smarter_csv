PREVIOUS: [Header Transformations](./header_transformations.md) | NEXT: [Data Transformations](./data_transformations.md)
----------------

# Header Validations

When you are importing data, it can be important to verify that all required data is present, to ensure consistent quality when importing data.

You can use the `required_keys` option to specify an array of hash keys that you require to be present at a minimum for every data row (after header transformation).

If these keys are not present, `SmarterCSV::MissingKeys` will be raised to inform you of the data inconsistency.

## Example

```ruby
  options = {
    required_keys: [:source_account, :destination_account, :amount]
  }
  data = SmarterCSV.process("/tmp/transactions.csv", options)

  => this will raise SmarterCSV::MissingKeys if any row does not contain these three keys
```

----------------
PREVIOUS: [Header Transformations](./header_transformations.md) | NEXT: [Data Transformations](./data_transformations.md)
