
### Contents

  * [Introduction](./_introduction.md)
  * [The Basic API](./basic_api.md)
  * [Batch Processing](././batch_processing.md)
  * [Configuration Options](./options.md)
  * [Row and Column Separators](./row_col_sep.md)
  * [**Header Transformations**](./header_transformations.md)
  * [Header Validations](./header_validations.md)
  * [Data Transformations](./data_transformations.md)
  * [Value Converters](./value_converters.md)
    
--------------  

# Header Transformations

By default SmarterCSV assumes that a CSV file has headers, and it automatically normalizes the headers and transforms them into Ruby symbols. You can completely customize or override this (see below).

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

## Key Mapping

The above example already illustrates how intermediate keys can be mapped into something different.
This transfoms some of the keys in the input, but other keys are still present.

There is an additional option `remove_unmapped_keys` which can be enabled to only produce the mapped keys in the resulting hashes, and drops any other columns.

 
### NOTES on Key Mapping:
 * keys in the header line of the file can be re-mapped to a chosen set of symbols, so the resulting Hashes can be better used internally in your application (e.g. when directly creating MongoDB entries with them)
 * if you want to completely delete a key, then map it to nil or to '', they will be automatically deleted from any result Hash
 * if you have input files with a large number of columns, and you want to ignore all columns which are not specifically mapped with :key_mapping, then use option :remove_unmapped_keys => true

## CSV Files without Headers

If you have CSV files without headers, it is important to set `headers_in_file: false`, otherwise you'll lose the first data line in your file.
You then have to provide `user_provided_headers`, which takes an array of either symbols or strings.


## CSV Files with Headers

For CSV files with headers, you can either:

* use the automatic header normalization
* map one or more headers into whatever you chose using the `map_headers` option.
  (if you map a header to `nil`, it will remove that column from the resulting row hash).
* completely replace the headers using `user_provided_headers` (please be careful with this powerful option, as it is not robust against changes in input format).
* use the original unmodified headers from the CSV file, using `keep_original_headers`. This results in hash keys that are strings, and may be padded with spaces.


# Notes

### NOTES about CSV Headers:
 * as this method parses CSV files, it is assumed that the first line of any file will contain a valid header
 * the first line with the header might be commented out, in which case you will need to set `comment_regexp: /\A#/`
 * any occurences of :comment_regexp or :row_sep will be stripped from the first line with the CSV header
 * any of the keys in the header line will be downcased, spaces replaced by underscore, and converted to Ruby symbols before being used as keys in the returned Hashes
 * you can not combine the :user_provided_headers and :key_mapping options
 * if the incorrect number of headers are provided via :user_provided_headers, exception SmarterCSV::HeaderSizeMismatch is raised

### NOTES on improper quotation and unwanted characters in headers:
 * some CSV files use un-escaped quotation characters inside fields. This can cause the import to break. To get around this, use the `:force_simple_split => true` option in combination with `:strip_chars_from_headers => /[\-"]/` . This will also significantly speed up the import.
   If you would force a different :quote_char instead (setting it to a non-used character), then the import would be up to 5-times slower than using `:force_simple_split`.

---------------
PREVIOUS: [Row and Column Separators](./row_col_sep.md) | NEXT: [Header Validations](./header_validations.md) 

