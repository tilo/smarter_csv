
### Contents

  * [Introduction](./_introduction.md)
  * [**The Basic API**](./basic_api.md)
  * [Batch Processing](././batch_processing.md)
  * [Configuration Options](./options.md)
  * [Row and Column Separators](./row_col_sep.md)
  * [Header Transformations](./header_transformations.md)
  * [Header Validations](./header_validations.md)
  * [Data Transformations](./data_transformations.md)
  * [Value Converters](./value_converters.md)
    
--------------  

# SmarterCSV Basic API

Let's explore the basic APIs for reading and writing CSV files. There is a simplified API (backwards conpatible with previous SmarterCSV versions) and the full API, which allows you to access the internal state of the reader or writer instance after processing.

## Reading CSV

SmarterCSV has convenient defaults for automatically detecting row and column separators based on the given data. This provides more robust parsing of input files when you have no control over the data, e.g. when users upload CSV files.
Learn more about this [in this section](docs/examples/row_col_sep.md).

### Simplified Interface

The simplified call to read CSV files is:

      ```
         array_of_hashes = SmarterCSV.process(file_or_input, options, &block)

      ```
It can also be used with a block:

      ```
         SmarterCSV.process(file_or_input, options, &block) do |hash|
            # process one row of CSV
         end
      ```

It can also be used for processing batches of rows:

      ```
         SmarterCSV.process(file_or_input, {chunk_size: 100}, &block) do |array_of_hashes|
            # process one chunk of up to 100 rows of CSV data
         end
      ```

### Full Interface

The simplified API works in most cases, but if you need access to the internal state and detailed results of the CSV-parsing, you should use this form:

      ```
        reader = SmarterCSV::Reader.new(file_or_input, options)
        data = reader.process

        puts reader.raw_headers
      ```
It cal also be used with a block:

      ```      
        reader = SmarterCSV::Reader.new(file_or_input, options)
        data = reader.process do 
           # do something here
        end

        puts reader.raw_headers
      ```

This allows you access to the internal state of the `reader` instance after processing.


## Interface for Writing CSV

To generate a CSV file, we use the `<<` operator to append new data to the file.

The input operator for adding data to a CSV file `<<` can handle single hashes, array-of-hashes, or array-of-arrays-of-hashes, and can be called one or multiple times for each file.

One smart feature of writing CSV data is the discovery of headers. 

If you have hashes of data, where each hash can have different keys, the `SmarterCSV::Reader` automatically discovers the superset of keys as the headers of the CSV file. This can be disabled by either providing one of the options `headers`, `map_headers`, or `discover_headers: false`.


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
        writer = SmarterCSV::Writer.new(file_path, options)

        MyModel.find_in_batches(batch_size: 100) do |batch|
          batch.pluck(:name, :description, :instructor).each do |record|
            csv_writer << record
          end

        writer.finalize
      ```

## Rescue from Exceptions

While SmarterCSV uses sensible defaults to process the most common CSV files, it will raise exceptions if it can not auto-detect `col_sep`, `row_sep`, or if it encounters other problems. Therefore please rescue from `SmarterCSV::Error`, and handle outliers according to your requirements.

If you encounter unusual CSV files, please follow the tips in the Troubleshooting section below. You can use the options below to accomodate for unusual formats.

## Troubleshooting

In case your CSV file is not being parsed correctly, try to examine it in a text editor. For closer inspection  a tool like `hexdump` can help find otherwise hidden control character or byte sequences like [BOMs](https://en.wikipedia.org/wiki/Byte_order_mark).

```
$ hexdump -C spec/fixtures/bom_test_feff.csv
00000000  fe ff 73 6f 6d 65 5f 69  64 2c 74 79 70 65 2c 66  |..some_id,type,f|
00000010  75 7a 7a 62 6f 78 65 73  0d 0a 34 32 37 36 36 38  |uzzboxes..427668|
00000020  30 35 2c 7a 69 7a 7a 6c  65 73 2c 31 32 33 34 0d  |05,zizzles,1234.|
00000030  0a 33 38 37 35 39 31 35  30 2c 71 75 69 7a 7a 65  |.38759150,quizze|
00000040  73 2c 35 36 37 38 0d 0a                           |s,5678..|
```

## Assumptions / Limitations

* the escape character is `\`, as on UNIX and Windows systems.
* quote charcters around fields are balanced, e.g. valid: `"field"`, invalid: `"field\"`
  e.g. an escaped `quote_char` does not denote the end of a field.


## NOTES about File Encodings:
 * if you have a CSV file which contains unicode characters, you can process it as follows:

```ruby
       File.open(filename, "r:bom|utf-8") do |f|
         data = SmarterCSV.process(f);
       end
```
* if the CSV file with unicode characters is in a remote location, similarly you need to give the encoding as an option to the `open` call:
```ruby
       require 'open-uri'
       file_location = 'http://your.remote.org/sample.csv'
       open(file_location, 'r:utf-8') do |f|   # don't forget to specify the UTF-8 encoding!!
         data = SmarterCSV.process(f)
       end
```

----------------
PREVIOUS: [Introduction](./_introduction.md) | NEXT: [Batch Processing](./batch_processing.md)
