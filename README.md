
# SmarterCSV

 [![codecov](https://codecov.io/gh/tilo/smarter_csv/branch/main/graph/badge.svg?token=1L7OD80182)](https://codecov.io/gh/tilo/smarter_csv) [![Gem Version](https://badge.fury.io/rb/smarter_csv.svg)](http://badge.fury.io/rb/smarter_csv)

 SmarterCSV provides a convenient interface for reading and writing CSV files and data.

 Unlike traditional CSV parsing methods, SmarterCSV focuses on representing the data for each row as a Ruby hash, which lends itself perfectly for direct use with ActiveRecord, Sidekiq, and JSON stores such as S3. For large files it supports processing CSV data in chunks of array-of-hashes, which allows parallel or batch processing of the data.

 Its powerful interface is designed to simplify and optimize the process of handling CSV data, and allows for highly customizable and efficient data processing by enabling the user to easily map CSV headers to Hash keys, skip unwanted rows, and transform data on-the-fly. 

 This results in a more readable, maintainable, and performant codebase. Whether you're dealing with large datasets or complex data transformations, SmarterCSV streamlines CSV operations, making it an invaluable tool for developers seeking to enhance their data processing workflows.

  When writing CSV data to file, it similarly takes arrays of hashes, and converts them to a CSV file.

One user wrote:

        *Best gem for CSV for us yet. [...] taking an import process from 7+ hours to about 3 minutes.
   [...] Smarter CSV was a big part and helped clean up our code ALOT*

# API

There is a simplified call for reading and writing, that wraps the underlying 

## Reading CSV

Convenient default allow automatic detection of the column and row separators: `row_sep: :auto`, `col_sep: :auto`. This makes it easier to process any CSV files without having to examine the line endings or column separators, e.g. when users upload CSV files to your service.

You can change the setting `:auto_row_sep_chars` to only analyze the first N characters of the file (default is 500 characters); `nil` or `0` will check the whole file). Of course you can also set the `:row_sep` manually.


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

        # either simple one-liner:
        data = reader.process

        # or block format:
        data = reader.process do 
           # do something here
        end
      ```

This gives you access to the internal state of the `reader` instance.


## Interface for Writing CSV

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

## Assumptions / Limitations
* It is assumed that the escape character is `\`, as on UNIX and Windows systems.
* It is assumed that quote charcters around fields are balanced, e.g. valid: `"field"`, invalid: `"field\"`
  e.g. an escaped `quote_char` does not denote the end of a field.
* This Gem is only for importing CSV files - writing of CSV files is not supported at this time.


# Features

# Examples


# Articles
* [Processing 1.4 Million CSV Records in Ruby, fast ](https://lcx.wien/blog/processing-14-million-csv-records-in-ruby/)
* [Speeding up CSV parsing with parallel processing](http://xjlin0.github.io/tech/2015/05/25/faster-parsing-csv-with-parallel-processing)
* The [original post](http://www.unixgods.org/Ruby/process_csv_as_hashes.html) that started SmarterCSV:


# Notes

## NOTES about CSV Headers:
 * as this method parses CSV files, it is assumed that the first line of any file will contain a valid header
 * the first line with the header might be commented out, in which case you will need to set `comment_regexp: /\A#/`
   This is no longer handled automatically since 1.5.0.
 * any occurences of :comment_regexp or :row_sep will be stripped from the first line with the CSV header
 * any of the keys in the header line will be downcased, spaces replaced by underscore, and converted to Ruby symbols before being used as keys in the returned Hashes
 * you can not combine the :user_provided_headers and :key_mapping options
 * if the incorrect number of headers are provided via :user_provided_headers, exception SmarterCSV::HeaderSizeMismatch is raised

## NOTES on Duplicate Headers:
 As a corner case, it is possible that a CSV file contains multiple headers with the same name. 
 * If that happens, by default `smarter_csv` will raise a `DuplicateHeaders` error.
 * If you set `duplicate_header_suffix` to a non-nil string, it will use it to append numbers 2..n to the duplicate headers. To further disambiguate the headers, you can further use `key_mapping` to assign meaningful names.
 * If your code will need to process arbitrary CSV files, please set `duplicate_header_suffix`.
 * Another way to deal with duplicate headers it to use `user_assigned_headers` to ignore any headers in the file.

## NOTES on Key Mapping:
 * keys in the header line of the file can be re-mapped to a chosen set of symbols, so the resulting Hashes can be better used internally in your application (e.g. when directly creating MongoDB entries with them)
 * if you want to completely delete a key, then map it to nil or to '', they will be automatically deleted from any result Hash
 * if you have input files with a large number of columns, and you want to ignore all columns which are not specifically mapped with :key_mapping, then use option :remove_unmapped_keys => true

## NOTES on the use of Chunking and Blocks:
 * chunking can be VERY USEFUL if used in combination with passing a block to File.read_csv FOR LARGE FILES
 * if you pass a block to File.read_csv, that block will be executed and given an Array of Hashes as the parameter.
 * if the chunk_size is not set, then the array will only contain one Hash.
 * if the chunk_size is > 0 , then the array may contain up to chunk_size Hashes.
 * this can be very useful when passing chunked data to a post-processing step, e.g. through Resque

## NOTES on improper quotation and unwanted characters in headers:
 * some CSV files use un-escaped quotation characters inside fields. This can cause the import to break. To get around this, use the `:force_simple_split => true` option in combination with `:strip_chars_from_headers => /[\-"]/` . This will also significantly speed up the import.
   If you would force a different :quote_char instead (setting it to a non-used character), then the import would be up to 5-times slower than using `:force_simple_split`.

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

# Options

## CSV Writing

     | Option                      | Default  |  Explanation                                                                         |
     ---------------------------------------------------------------------------------------------------------------------------------
     | :row_sep                    |   "\n"    | Separates rows
     | :col_sep                    |   ","     | Separates each value in a row
     | :quote_char                 |   '"'     | 
     | :force_quotes               |   false   | Forces each individual value to be quoted
     | :discover_headers           |   true    | Automatically detects all keys in the input before writing the header
     |                             |           | This can be disabled by providing `headers` or `map_headers` options.
     | :headers                    |    []     | You can provide the specific list of keys from the input you'd like to be used as headers in the CSV file |
     | :map_headers                |    {}     | Similar to `headers`, but also maps each desired key to a user-specified value that is uesd as the header. | 
     |

## CSV Reading

     | Option                      | Default  |  Explanation                                                                         |
     ---------------------------------------------------------------------------------------------------------------------------------
     | :chunk_size                 |   nil    | if set, determines the desired chunk-size (defaults to nil, no chunk processing)     |
     |                             |          |                                                                                      |
     | :file_encoding              |   utf-8  | Set the file encoding eg.: 'windows-1252' or 'iso-8859-1'                            |
     | :invalid_byte_sequence      |   ''     | what to replace invalid byte sequences with                                          |
     | :force_utf8                 |   false  | force UTF-8 encoding of all lines (including headers) in the CSV file                |
     | :skip_lines                 |   nil    | how many lines to skip before the first line or header line is processed             |
     | :comment_regexp             |   nil    | regular expression to ignore comment lines (see NOTE on CSV header), e.g./\A#/       |
     ---------------------------------------------------------------------------------------------------------------------------------
     | :col_sep                    |   :auto   | column separator (default was ',')                                           |
     | :force_simple_split         |   false  | force simple splitting on :col_sep character for non-standard CSV-files.             |
     |                             |          | e.g. when :quote_char is not properly escaped                                        |
     | :row_sep                    |  :auto   | row separator or record separator (previous default was system's $/ , which defaulted to "\n") |
     |                             |          | This can also be set to :auto, but will process the whole cvs file first  (slow!)    |
     | :auto_row_sep_chars         |   500    | How many characters to analyze when using `:row_sep => :auto`. nil or 0 means whole file. |
     | :quote_char                 |   '"'    | quotation character                                                                  |
     ---------------------------------------------------------------------------------------------------------------------------------
     | :headers_in_file            |   true   | Whether or not the file contains headers as the first line.                          |
     |                             |          | Important if the file does not contain headers,                                      |
     |                             |          | otherwise you would lose the first line of data.                                     |
     | :duplicate_header_suffix    |   ''     | Adds numbers to duplicated headers and separates them by the given suffix.           |
     |                             |          | Set this to nil to raise `DuplicateHeaders` error instead (previous behavior)        |
     | :user_provided_headers      |   nil    | *careful with that axe!*                                                             |
     |                             |          | user provided Array of header strings or symbols, to define                          |
     |                             |          | what headers should be used, overriding any in-file headers.                         |
     |                             |          | You can not combine the :user_provided_headers and :key_mapping options              |
     | :remove_empty_hashes        |   true   | remove / ignore any hashes which don't have any key/value pairs or all empty values  |
     | :verbose                    |   false  | print out line number while processing (to track down problems in input files)       |
     | :with_line_numbers          |   false  | add :csv_line_number to each data hash                                               |
     ---------------------------------------------------------------------------------------------------------------------------------

Additional 1.x Options which may be replaced in 2.0

There have been a lot of 1-offs and feature creep around these options, and going forward we'll strive to have a simpler, but more flexible way to address these features.


     | Option                      | Default  |  Explanation                                                                         |
     ---------------------------------------------------------------------------------------------------------------------------------
     | :key_mapping                |   nil    | a hash which maps headers from the CSV file to keys in the result hash               |
     | :silence_missing_keys        |   false  | ignore missing keys in `key_mapping`                                   |
     |                             |          | if set to true: makes all mapped keys optional                         |
     |                             |          | if given an array, makes only the keys listed in it optional                         |
     | :required_keys              |   nil    | An array. Specify the required names AFTER header transformation.                  |
     | :required_headers           |   nil    | (DEPRECATED / renamed) Use `required_keys` instead                          |
     |                             |          | or an exception is raised   No validation if nil is given.                           |
     | :remove_unmapped_keys       |   false  | when using :key_mapping option, should non-mapped keys / columns be removed?         |
     | :downcase_header            |   true   | downcase all column headers                                                          |
     | :strings_as_keys            |   false  | use strings instead of symbols as the keys in the result hashes                      |
     | :strip_whitespace           |   true   | remove whitespace before/after values and headers                                    |
     | :keep_original_headers      |   false  | keep the original headers from the CSV-file as-is.                                   |
     |                             |          | Disables other flags manipulating the header fields.                                 |
     | :strip_chars_from_headers   |   nil    | RegExp to remove extraneous characters from the header line (e.g. if headers are quoted) |
     ---------------------------------------------------------------------------------------------------------------------------------
     | :value_converters           |   nil    | supply a hash of :header => KlassName; the class needs to implement self.convert(val)|
     | :remove_empty_values        |   true   | remove values which have nil or empty strings as values                              |
     | :remove_zero_values         |   false  | remove values which have a numeric value equal to zero / 0                           |
     | :remove_values_matching     |   nil    | removes key/value pairs if value matches given regular expressions. e.g.:            |
     |                             |          | /^\$0\.0+$/ to match $0.00 , or /^#VALUE!$/ to match errors in Excel spreadsheets    |
     | :convert_values_to_numeric  |   true   | converts strings containing Integers or Floats to the appropriate class              |
     |                             |          |      also accepts either {:except => [:key1,:key2]} or {:only => :key3}              |
     ---------------------------------------------------------------------------------------------------------------------------------

# Troubleshooting

In case your CSV file is not being parsed correctly, try to examine it in a text editor. For closer inspection  a tool like `hexdump` can help find otherwise hidden control character or byte sequences like [BOMs](https://en.wikipedia.org/wiki/Byte_order_mark).

```
$ hexdump -C spec/fixtures/bom_test_feff.csv
00000000  fe ff 73 6f 6d 65 5f 69  64 2c 74 79 70 65 2c 66  |..some_id,type,f|
00000010  75 7a 7a 62 6f 78 65 73  0d 0a 34 32 37 36 36 38  |uzzboxes..427668|
00000020  30 35 2c 7a 69 7a 7a 6c  65 73 2c 31 32 33 34 0d  |05,zizzles,1234.|
00000030  0a 33 38 37 35 39 31 35  30 2c 71 75 69 7a 7a 65  |.38759150,quizze|
00000040  73 2c 35 36 37 38 0d 0a                           |s,5678..|
```

-------------------------------------------------------------------------------------

#### SmarterCSV 1.x [Current Version]

`smarter_csv` is a Ruby Gem for convenient importing of CSV Files as Array(s) of Hashes, suitable for direct processing with ActiveRecord, parallel processing, kicking-off batch jobs with Sidekiq, or oploading data to S3.

The goals for SmarterCSV are: 
  * ease of use for handling most common CSV files without having to tweak options
  * improve robustness of your code when you have no control over the quality of the CSV files which are processed
  * formatting each row of data as a hash, in order to allow easy processing with ActiveRecord, parallel processing, kicking-off batch jobs with Sidekiq, or oploading data to S3.


#### Features

`smarter_csv` has lots of features:
 * able to process large CSV-files
 * able to chunk the input from the CSV file to avoid loading the whole CSV file into memory
 * return a Hash for each line of the CSV file, so we can quickly use the results for either creating MongoDB or ActiveRecord entries, or further processing with Resque
 * able to pass a block to the `process` method, so data from the CSV file can be directly processed (e.g. Resque.enqueue )
 * allows to have a bit more flexible input format, where comments are possible, and col_sep,row_sep can be set to any character sequence, including control characters.
 * able to re-map CSV "column names" to Hash-keys of your choice (normalization)
 * able to ignore "columns" in the input (delete columns)
 * able to eliminate nil or empty fields from the result hashes (default)

### Why SmartercSV?

Ruby's CSV library's API is pretty old, and it's processing of CSV-files returning Arrays of Arrays feels 'very close to the metal'. The output is not easy to use - especially not if you want to create database records or Sidekiq jobs with it. Another shortcoming is that Ruby's CSV library does not have good support for huge CSV-files, e.g. there is no support for 'chunking' and/or parallel processing of the CSV-content (e.g. with Sidekiq).

As the existing CSV libraries didn't fit my needs, I was writing my own CSV processing - specifically for use in connection with Rails ORMs like Mongoid, MongoMapper and ActiveRecord. In those ORMs you can easily pass a hash with attribute/value pairs to the create() method. The lower-level Mongo driver and Moped also accept larger arrays of such hashes to create a larger amount of records quickly with just one call. The same patterns are used when you pass data to Sidekiq jobs.

For processing large CSV files it is essential to process them in chunks, so the memory impact is minimized.

### How?

The two main choices you have in terms of how to call `SmarterCSV.process` are:
 * calling `process` with or without a block
 * passing a `:chunk_size` to the `process` method, and processing the CSV-file in chunks, rather than in one piece.

-------------------------------------------------------------------------------------

# Installation

Add this line to your application's Gemfile:
```ruby
    gem 'smarter_csv'
```
And then execute:
```ruby
    $ bundle
```
Or install it yourself as:
```ruby
    $ gem install smarter_csv
```
# [ChangeLog](./CHANGELOG.md)

# Reporting Bugs / Feature Requests

Please [open an Issue on GitHub](https://github.com/tilo/smarter_csv/issues) if you have feedback, new feature requests, or want to report a bug. Thank you!

For reporting issues, please:
  * include a small sample CSV file
  * open a pull-request adding a test that demonstrates the issue
  * mention your version of SmarterCSV, Ruby, Rails

# [A Special Thanks to all Contributors!](CONTRIBUTORS.md) 🎉🎉🎉


# Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Added some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request

