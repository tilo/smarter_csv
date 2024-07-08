# Header Transformations

By default SmarterCSV assumes that a CSV file has headers, and it automatically normalizes the headers and transforms them into Ruby symbols. You can completely customize or override this (see below).

## Header Normalization

When processing the headers, it transforms them into Ruby symbols, stripping extra spaces, lower-casing them and replacing spaces with underscores. e.g. " \t Annual Sales  " becomes `:annual_sales`. 

## Duplicate Headers

There can be a lot of variation in CSV files. It is possible that a CSV file contains multiple headers with the same name. 

By default SmarterCSV handles duplicate headers by appending numbers 2..n to them.

```
$ cat > /tmp/dupe.csv
name,name,name
Carl,Edward,Sagan
```

when parsing these duplicate headers, it will return:

```
  data = SmarterCSV.process('/tmp/dupe.csv')
   => [{:name=>"Carl", :name2=>"Edward", :name3=>"Sagan"}]
```

If you want to have an underscore between the header and the number, you can set `duplicate_header_suffix: ' '`.

```
  data = SmarterCSV.process('/tmp/dupe.csv', {duplicate_header_suffix: '_'})
   => [{:name=>"Carl", :name_2=>"Edward", :name_3=>"Sagan"}]
```
 
 To further disambiguate the headers, you can further use `key_mapping` to assign meaningful names, e.g. 
   
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

