
### Contents

  * [Introduction](./_introduction.md)
  * [Parsing Strategy](./parsing_strategy.md)
  * [The Basic Read API](./basic_read_api.md)
  * [**The Basic Write API**](./basic_write_api.md)
  * [Batch Processing](././batch_processing.md)
  * [Configuration Options](./options.md)
  * [Row and Column Separators](./row_col_sep.md)
  * [Header Transformations](./header_transformations.md)
  * [Header Validations](./header_validations.md)
  * [Data Transformations](./data_transformations.md)
  * [Value Converters](./value_converters.md)
    
--------------  

# SmarterCSV Basic Write API

Let's explore the basic API for writing CSV files. There is a simplified API (backwards conpatible with previous SmarterCSV versions) and the full API, which allows you to access the internal state of the writer instance after processing.

## Writing CSV Files

To generate a CSV file, we use the `<<` operator to append new data to the file.

The input operator for adding data to a CSV file `<<` can handle single hashes, array-of-hashes, or array-of-arrays-of-hashes, and can be called one or multiple times in order to create a file.

### Auto-Discovery of Headers

By default, the `SmarterCSV::Writer` discovers all keys that are present in the input data, and as they become know, appends them to the CSV headers. This ensures that all data will be included in the output CSV file.

If you want to customize the output file, or only include select headers, check the section about Advanced Features below.

### Auto-Quoting of Problematic Values

CSV files use some special characters that are important for the CSV format to function:
* @row_sep : typically `\n` the carriage return
* @col_sep : typically `,` the comma
* @quote_char : typically `"` the double-quote
  
When your data for a given field in a CSV row contains either of these characters, we need to prevent them to break the CSV file format.

`SmarterCSV::Writer` automatically detects if a field contains either of these three characters. If a field contains the `@quote_char`, it will be prefixed by another `@qoute_char` as per CSV conventions.
In either case the corresponding field will be put in double-quotes. 
  

### Simplified Interface

The simplified interface takes a block:

      ```
        SmarterCSV.generate(filename, options) do |csv_writer|

         MyModel.find_in_batches(batch_size: 100) do |batch|
           batch.pluck(:name, :description, :instructor).each do |record|
             csv_writer << record
           end
         end

       end
     ```

### Full Interface

      ```
        csv_writer = SmarterCSV::Writer.new(file_path, options)

        MyModel.find_in_batches(batch_size: 100) do |batch|
          batch.pluck(:name, :description, :instructor).each do |record|
            csv_writer << record
          end

        csv_writer.finalize
      ```

## Advanced Features: Customizing the Output Format

You can customize the output format through different features.

In the options, you can pass-in either of these parameters to customize your output format.
* `headers`, which limits the CSV headers to just the specified list.
* `map_header`, which maps a given list of Hash keys to custom strings, and limits the CSV headers to just those.
* `value_converters`, which specifies a hash with more advanced value transformations.

### Limited Headers

You can use the `headers` option to limit the CSV headers to only a sub-set of Hash keys from your data.
This will switch-off the automatic detection of headers, and limit the CSV output file to only the CSV headers you provide in this option.


### Mapping Headers

Similar to the `headers` option, you can define `map_headers` in order to rename a given set of Hash keys to some custom strings in order to rename them in the CSV header. This will switch-off the automatic detection of headers.


### Per Key Value Converters


Using per-key value converters, you can control how specific hash keys in your data are converted in the output.

Example 1:

```
      options = {
        value_converters: {
          active: ->(v) { !!v ? 'YES' : 'NO' },
        }
      }
```

This maps the boolean value of the hash key `:active` into strings `"YES"`, `"NO"`.

Example 2:

```
      options = {
        value_converters: {
          active: ->(v) { !!v ? '✅' : '❌' },
          balance: ->(v) do
            case v
            when Float
              '$%.2f' % v.round(2)
            when Integer
              "$#{v}"
            else
              v.to_s
            end
          end,
        }
      }
```

This maps the hash key `:balance` to a string. Floats are rounded and displayed with 2 decimals and prefixed by `$`. Integers are prefixed by `$`.
The boolean value of the key `:active` is mapped into an emoji.

### Global Value Converters

You can also use the special keyword `:_all` to define transformations that are applied to each field of the CSV file.

```
      options = {
        value_converters: {        
          disable_auto_quoting: true, # ⚠️ Important: turn off auto-quoting because we're messing with it below
          active: ->(v) { !!v ? 'YES' : 'NO' },
          _all: ->(_k, v) { v.is_a?(String) ? "\"#{v}\"" : v } # only double-quote string fields
        }  
      }
```

Using the `:_all` keyword, you can set up rules to convert all hash keys. This is applied after all per-key conversions are made.

This example puts double-quotes around all String-value data, but leaves other types unchanged.

Note that when you're customizing putting quote-chars around fields, you need to `disable_auto_quoting`.

## More Examples

Check out the [RSpec tests](../spec/smarter_csv/writer_spec.rb) for more examples.

----------------
PREVIOUS: [The Basic Read API](./basic_read_api.md) | NEXT: [Batch Processing](./batch_processing.md)
