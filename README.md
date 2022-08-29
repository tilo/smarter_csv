
# SmarterCSV

 [![codecov](https://codecov.io/gh/tilo/smarter_csv/branch/main/graph/badge.svg?token=1L7OD80182)](https://codecov.io/gh/tilo/smarter_csv) [![Gem Version](https://badge.fury.io/rb/smarter_csv.svg)](http://badge.fury.io/rb/smarter_csv)
 
#### Work towards Future Version 2.0

* Work towards SmarterCSV 2.0 is still ongoing, with improved features, and more streamlined options, but consider it as experimental at this time.
  Please check the [2.0-develop branch](https://github.com/tilo/smarter_csv/tree/2.0-develop), open any issues and pull requests with mention of tag v2.0.

* New versions of SmarterCSV 1.x will soon print a deprecation warning if you set :verbose to true
  See below for list of deprecated options.

#### Restructured Branches

* default branch is `main` for 1.x development
* 2.x development is on `2.0-development`

---------------

#### SmarterCSV 1.x [Current Version]

`smarter_csv` is a Ruby Gem for smarter importing of CSV Files as Array(s) of Hashes, suitable for direct processing with ActiveRecord, parallel processing, or kicking-off batch jobs with Sidekiq.

To create high-quality output, some options are enabled as a default. Please make sure to check the output and tweak the options accordingly.

One `smarter_csv` user wrote:

  *Best gem for CSV for us yet. [...] taking an import process from 7+ hours to about 3 minutes.
   [...] Smarter CSV was a big part and helped clean up our code ALOT*

`smarter_csv` has lots of features:
 * able to process large CSV-files
 * able to chunk the input from the CSV file to avoid loading the whole CSV file into memory
 * return a Hash for each line of the CSV file, so we can quickly use the results for either creating MongoDB or ActiveRecord entries, or further processing with Resque
 * able to pass a block to the `process` method, so data from the CSV file can be directly processed (e.g. Resque.enqueue )
 * allows to have a bit more flexible input format, where comments are possible, and col_sep,row_sep can be set to any character sequence, including control characters.
 * able to re-map CSV "column names" to Hash-keys of your choice (normalization)
 * able to ignore "columns" in the input (delete columns)
 * able to eliminate nil or empty fields from the result hashes (default)

NOTE; This Gem is only for importing CSV files - writing of CSV files is not supported at this time.

### Why?

Ruby's CSV library's API is pretty old, and it's processing of CSV-files returning Arrays of Arrays feels 'very close to the metal'. The output is not easy to use - especially not if you want to create database records or Sidekiq jobs with it. Another shortcoming is that Ruby's CSV library does not have good support for huge CSV-files, e.g. there is no support for 'chunking' and/or parallel processing of the CSV-content (e.g. with Sidekiq).

As the existing CSV libraries didn't fit my needs, I was writing my own CSV processing - specifically for use in connection with Rails ORMs like Mongoid, MongoMapper and ActiveRecord. In those ORMs you can easily pass a hash with attribute/value pairs to the create() method. The lower-level Mongo driver and Moped also accept larger arrays of such hashes to create a larger amount of records quickly with just one call. The same patterns are used when you pass data to Sidekiq jobs.

For processing large CSV files it is essential to process them in chunks, so the memory impact is minimized.

### How?

The two main choices you have in terms of how to call `SmarterCSV.process` are:
 * calling `process` with or without a block
 * passing a `:chunk_size` to the `process` method, and processing the CSV-file in chunks, rather than in one piece.

Tip: If you are uncertain about what line endings a CSV-file uses, try specifying `:row_sep => :auto` as part of the options.
But this could be slow if we would analyze the whole CSV file first (previous to 1.1.5 the whole file was analyzed).
To speed things up, you can setting the option `:auto_row_sep_chars` to only analyze the first N characters of the file (default is 500; nil or 0 will check the whole file).
You can also set the `:row_sep` manually! Checkout Example 5 for unusual `:row_sep` and `:col_sep`.


#### Example 1a: How SmarterCSV processes CSV-files as array of hashes:
Please note how each hash contains only the keys for columns with non-null values.

```ruby
     $ cat pets.csv
     first name,last name,dogs,cats,birds,fish
     Dan,McAllister,2,,,
     Lucy,Laweless,,5,,
     Miles,O'Brian,,,,21
     Nancy,Homes,2,,1,
     $ irb
     > require 'smarter_csv'
      => true
     > pets_by_owner = SmarterCSV.process('/tmp/pets.csv')
      => [ {:first_name=>"Dan", :last_name=>"McAllister", :dogs=>"2"},
           {:first_name=>"Lucy", :last_name=>"Laweless", :cats=>"5"},
           {:first_name=>"Miles", :last_name=>"O'Brian", :fish=>"21"},
           {:first_name=>"Nancy", :last_name=>"Homes", :dogs=>"2", :birds=>"1"}
         ]
```


#### Example 1b: How SmarterCSV processes CSV-files as chunks, returning arrays of hashes:
Please note how the returned array contains two sub-arrays containing the chunks which were read, each chunk containing 2 hashes.
In case the number of rows is not cleanly divisible by `:chunk_size`, the last chunk contains fewer hashes.

```ruby
     > pets_by_owner = SmarterCSV.process('/tmp/pets.csv', {:chunk_size => 2, :key_mapping => {:first_name => :first, :last_name => :last}})
       => [ [ {:first=>"Dan", :last=>"McAllister", :dogs=>"2"}, {:first=>"Lucy", :last=>"Laweless", :cats=>"5"} ],
            [ {:first=>"Miles", :last=>"O'Brian", :fish=>"21"}, {:first=>"Nancy", :last=>"Homes", :dogs=>"2", :birds=>"1"} ]
          ]
```

#### Example 1c: How SmarterCSV processes CSV-files as chunks, and passes arrays of hashes to a given block:
Please note how the given block is passed the data for each chunk as the parameter (array of hashes),
and how the `process` method returns the number of chunks when called with a block

```ruby
     > total_chunks = SmarterCSV.process('/tmp/pets.csv', {:chunk_size => 2, :key_mapping => {:first_name => :first, :last_name => :last}}) do |chunk|
         chunk.each do |h|   # you can post-process the data from each row to your heart's content, and also create virtual attributes:
           h[:full_name] = [h[:first],h[:last]].join(' ')  # create a virtual attribute
           h.delete(:first) ; h.delete(:last)              # remove two keys
         end
         puts chunk.inspect   # we could at this point pass the chunk to a Resque worker..
       end

       [{:dogs=>"2", :full_name=>"Dan McAllister"}, {:cats=>"5", :full_name=>"Lucy Laweless"}]
       [{:fish=>"21", :full_name=>"Miles O'Brian"}, {:dogs=>"2", :birds=>"1", :full_name=>"Nancy Homes"}]
        => 2
```
#### Example 2: Reading a CSV-File in one Chunk, returning one Array of Hashes:
```ruby
    filename = '/tmp/input_file.txt' # TAB delimited file, each row ending with Control-M
    recordsA = SmarterCSV.process(filename, {:col_sep => "\t", :row_sep => "\cM"})  # no block given

    => returns an array of hashes
```
#### Example 3: Populate a MySQL or MongoDB Database with SmarterCSV:
```ruby
    # without using chunks:
    filename = '/tmp/some.csv'
    options = {:key_mapping => {:unwanted_row => nil, :old_row_name => :new_name}}
    n = SmarterCSV.process(filename, options) do |array|
          # we're passing a block in, to process each resulting hash / =row (the block takes array of hashes)
          # when chunking is not enabled, there is only one hash in each array
          MyModel.create( array.first )
    end

     => returns number of chunks / rows we processed
```

#### Example 4: Reading a CSV-like File, and Processing it with Sidekiq:
```ruby
    filename = '/tmp/strange_db_dump'   # a file with CRTL-A as col_separator, and with CTRL-B\n as record_separator (hello iTunes!)
    options = {
      :col_sep => "\cA", :row_sep => "\cB\n", :comment_regexp => /^#/,
      :chunk_size => 100 , :key_mapping => {:export_date => nil, :name => :genre}
    }
    n = SmarterCSV.process(filename, options) do |chunk|
        SidekiqWorkerClass.process_async(chunk ) # pass an array of hashes to Sidekiq workers for parallel processing
    end
    => returns number of chunks
```

#### Example 5: Populate a MongoDB Database in Chunks of 100 records with SmarterCSV:
```ruby
    # using chunks:
    filename = '/tmp/some.csv'
    options = {:chunk_size => 100, :key_mapping => {:unwanted_row => nil, :old_row_name => :new_name}}
    n = SmarterCSV.process(filename, options) do |chunk|
          # we're passing a block in, to process each resulting hash / row (block takes array of hashes)
          # when chunking is enabled, there are up to :chunk_size hashes in each chunk
          MyModel.collection.insert( chunk )   # insert up to 100 records at a time
    end

     => returns number of chunks we processed
```

#### Example 6: Using Value Converters

NOTE: If you use `key_mappings` and `value_converters`, make sure that the value converters has references the keys based on the final mapped name, not the original name in the CSV file.
```ruby
    $ cat spec/fixtures/with_dates.csv
    first,last,date,price
    Ben,Miller,10/30/1998,$44.50
    Tom,Turner,2/1/2011,$15.99
    Ken,Smith,01/09/2013,$199.99
    $ irb
    > require 'smarter_csv'
    > require 'date'

    # define a custom converter class, which implements self.convert(value)
    class DateConverter
      def self.convert(value)
        Date.strptime( value, '%m/%d/%Y') # parses custom date format into Date instance
      end
    end

    class DollarConverter
      def self.convert(value)
        value.sub('$','').to_f
      end
    end

    options = {:value_converters => {:date => DateConverter, :price => DollarConverter}}
    data = SmarterCSV.process("spec/fixtures/with_dates.csv", options)
    data[0][:date]
      => #<Date: 1998-10-30 ((2451117j,0s,0n),+0s,2299161j)>
    data[0][:date].class
      => Date
    data[0][:price]
      => 44.50
    data[0][:price].class
      => Float
```
## Parallel Processing
[Jack](https://github.com/xjlin0) wrote an interesting article about [Speeding up CSV parsing with parallel processing](http://xjlin0.github.io/tech/2015/05/25/faster-parsing-csv-with-parallel-processing)

## Documentation

The `process` method reads and processes a "generalized" CSV file and returns the contents either as an Array of Hashes,
or an Array of Arrays, which contain Hashes, or processes Chunks of Hashes via a given block.

    SmarterCSV.process(filename, options={}, &block)

The options and the block are optional.

`SmarterCSV.process` supports the following options:

#### Options:

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
     | :col_sep                    |   ','    | column separator, can be set to :auto                                                |
     | :force_simple_split         |   false  | force simple splitting on :col_sep character for non-standard CSV-files.             |
     |                             |          | e.g. when :quote_char is not properly escaped                                        |
     | :row_sep                    | $/ ,"\n" | row separator or record separator , defaults to system's $/ , which defaults to "\n" |
     |                             |          | This can also be set to :auto, but will process the whole cvs file first  (slow!)    |
     | :auto_row_sep_chars         |   500    | How many characters to analyze when using `:row_sep => :auto`. nil or 0 means whole file. |
     | :quote_char                 |   '"'    | quotation character                                                                  |
     ---------------------------------------------------------------------------------------------------------------------------------
     | :headers_in_file            |   true   | Whether or not the file contains headers as the first line.                          |
     |                             |          | Important if the file does not contain headers,                                      |
     |                             |          | otherwise you would lose the first line of data.                                     |
     | :duplicate_header_suffix    |   nil    | If set, adds numbers to duplicated headers and separates them by the given suffix    |
     | :user_provided_headers      |   nil    | *careful with that axe!*                                                             |
     |                             |          | user provided Array of header strings or symbols, to define                          |
     |                             |          | what headers should be used, overriding any in-file headers.                         |
     |                             |          | You can not combine the :user_provided_headers and :key_mapping options              |
     | :remove_empty_hashes        |   true   | remove / ignore any hashes which don't have any key/value pairs or all empty values  |
     | :verbose                    |   false  | print out line number while processing (to track down problems in input files)       |
     | :with_line_numbers          |   false  | add :csv_line_number to heach data hash                                              |
     ---------------------------------------------------------------------------------------------------------------------------------

#### Deprecated 1.x Options: to be replaced in 2.0

There have been a lot of 1-offs and feature creep around these options, and going forward we'll have a simpler, but more flexible way to address these features.

Instead of these options, there will be a new and more flexible way to process the header fields, as well as the fields in each line of the CSV.
And header and data validations will also be supported in 2.x

     | Option                      | Default  |  Explanation                                                                         |
     ---------------------------------------------------------------------------------------------------------------------------------
     | :key_mapping                |   nil    | a hash which maps headers from the CSV file to keys in the result hash               |
     | :required_headers           |   nil    | An array. Eacn of the given headers must be present after header manipulation,       |
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


#### NOTES about File Encodings:
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

#### NOTES about CSV Headers:
 * as this method parses CSV files, it is assumed that the first line of any file will contain a valid header
 * the first line with the header might be commented out, in which case you will need to set `comment_regexp: /\A#/`
   This is no longer handled automatically since 1.5.0.
 * any occurences of :comment_regexp or :row_sep will be stripped from the first line with the CSV header
 * any of the keys in the header line will be downcased, spaces replaced by underscore, and converted to Ruby symbols before being used as keys in the returned Hashes
 * you can not combine the :user_provided_headers and :key_mapping options
 * if the incorrect number of headers are provided via :user_provided_headers, exception SmarterCSV::HeaderSizeMismatch is raised

#### NOTES on Duplicate Headers:
 As a corner case, it is possible that a CSV file contains multiple headers with the same name. 
 * If that happens, by default `smarter_csv` will raise a `DuplicateHeaders` error.
 * If you set `duplicate_header_suffix` to a non-nil string, it will use it to append numbers 2..n to the duplicate headers. To further disambiguate the headers, you can further use `key_mapping` to assign meaningful names.
 * If your code will need to process arbitrary CSV files, please set `duplicate_header_suffix`.
 * Another way to deal with duplicate headers it to use `user_assigned_headers` to ignore any headers in the file.

#### NOTES on Key Mapping:
 * keys in the header line of the file can be re-mapped to a chosen set of symbols, so the resulting Hashes can be better used internally in your application (e.g. when directly creating MongoDB entries with them)
 * if you want to completely delete a key, then map it to nil or to '', they will be automatically deleted from any result Hash
 * if you have input files with a large number of columns, and you want to ignore all columns which are not specifically mapped with :key_mapping, then use option :remove_unmapped_keys => true

#### NOTES on the use of Chunking and Blocks:
 * chunking can be VERY USEFUL if used in combination with passing a block to File.read_csv FOR LARGE FILES
 * if you pass a block to File.read_csv, that block will be executed and given an Array of Hashes as the parameter.
 * if the chunk_size is not set, then the array will only contain one Hash.
 * if the chunk_size is > 0 , then the array may contain up to chunk_size Hashes.
 * this can be very useful when passing chunked data to a post-processing step, e.g. through Resque

#### NOTES on improper quotation and unwanted characters in headers:
 * some CSV files use un-escaped quotation characters inside fields. This can cause the import to break. To get around this, use the `:force_simple_split => true` option in combination with `:strip_chars_from_headers => /[\-"]/` . This will also significantly speed up the import.
   If you would force a different :quote_char instead (setting it to a non-used character), then the import would be up to 5-times slower than using `:force_simple_split`.

## See also:

  http://www.unixgods.org/~tilo/Ruby/process_csv_as_hashes.html



## Installation

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
## [ChangeLog](./CHANGELOG.md)

## Reporting Bugs / Feature Requests

Please [open an Issue on GitHub](https://github.com/tilo/smarter_csv/issues) if you have feedback, new feature requests, or want to report a bug. Thank you!

For reporting issues, please:
  * include a small sample CSV file
  * open a pull-request adding a test that demonstrates the issue
  * mention your version of SmarterCSV, Ruby, Rails

## [A Special Thanks to all Contributors!](CONTRIBUTORS.md) 🎉🎉🎉


## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Added some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request

