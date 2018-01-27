# SmarterCSV

[![Build Status](https://secure.travis-ci.org/tilo/smarter_csv.svg?branch=master)](http://travis-ci.org/tilo/smarter_csv) [![Gem Version](https://badge.fury.io/rb/smarter_csv.svg)](http://badge.fury.io/rb/smarter_csv)

---------------
#### Service Announcement

Work towards SmarterCSV 2.0 is on it's way, with much improved features, and more streamlined options.

Please check the 2.0-develop branch, and open issues marked v2.0 and leave your comments.

New versions on the 1.2 branch will soon print a deprecation warning if you set :verbose to true
See below for list of deprecated options.

---------------
#### SmarterCSV

`smarter_csv` is a Ruby Gem for smarter importing of CSV Files as Array(s) of Hashes, suitable for direct processing with Mongoid or ActiveRecord,
and parallel processing with Resque or Sidekiq.

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

Ruby's CSV library's API is pretty old, and it's processing of CSV-files returning Arrays of Arrays feels 'very close to the metal'. The output is not easy to use - especially not if you want to create database records from it. Another shortcoming is that Ruby's CSV library does not have good support for huge CSV-files, e.g. there is no support for 'chunking' and/or parallel processing of the CSV-content (e.g. with Resque or Sidekiq),

As the existing CSV libraries didn't fit my needs, I was writing my own CSV processing - specifically for use in connection with Rails ORMs like Mongoid, MongoMapper or ActiveRecord. In those ORMs you can easily pass a hash with attribute/value pairs to the create() method. The lower-level Mongo driver and Moped also accept larger arrays of such hashes to create a larger amount of records quickly with just one call.

### Examples

The two main choices you have in terms of how to call `SmarterCSV.process` are:
 * calling `process` with or without a block
 * passing a `:chunk_size` to the `process` method, and processing the CSV-file in chunks, rather than in one piece.

Tip: If you are uncertain about what line endings a CSV-file uses, try specifying `:row_sep => :auto` as part of the options.
But this could be slow if we would analyze the whole CSV file first (previous to 1.1.5 the whole file was analyzed).
To speed things up, you can setting the option `:auto_row_sep_chars` to only analyze the first N characters of the file (default is 500; nil or 0 will check the whole file).
You can also set the `:row_sep` manually! Checkout Example 5 for unusual `:row_sep` and `:col_sep`.


#### Example 1a: How SmarterCSV processes CSV-files as array of hashes:
Please note how each hash contains only the keys for columns with non-null values.

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


#### Example 1b: How SmarterCSV processes CSV-files as chunks, returning arrays of hashes:
Please note how the returned array contains two sub-arrays containing the chunks which were read, each chunk containing 2 hashes.
In case the number of rows is not cleanly divisible by `:chunk_size`, the last chunk contains fewer hashes.

     > pets_by_owner = SmarterCSV.process('/tmp/pets.csv', {:chunk_size => 2, :key_mapping => {:first_name => :first, :last_name => :last}})
       => [ [ {:first=>"Dan", :last=>"McAllister", :dogs=>"2"}, {:first=>"Lucy", :last=>"Laweless", :cats=>"5"} ],
            [ {:first=>"Miles", :last=>"O'Brian", :fish=>"21"}, {:first=>"Nancy", :last=>"Homes", :dogs=>"2", :birds=>"1"} ]
          ]

#### Example 1c: How SmarterCSV processes CSV-files as chunks, and passes arrays of hashes to a given block:
Please note how the given block is passed the data for each chunk as the parameter (array of hashes),
and how the `process` method returns the number of chunks when called with a block

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

#### Example 2: Reading a CSV-File in one Chunk, returning one Array of Hashes:

    filename = '/tmp/input_file.txt' # TAB delimited file, each row ending with Control-M
    recordsA = SmarterCSV.process(filename, {:col_sep => "\t", :row_sep => "\cM"})  # no block given

    => returns an array of hashes

#### Example 3: Populate a MySQL or MongoDB Database with SmarterCSV:

    # without using chunks:
    filename = '/tmp/some.csv'
    options = {:key_mapping => {:unwanted_row => nil, :old_row_name => :new_name}}
    n = SmarterCSV.process(filename, options) do |array|
          # we're passing a block in, to process each resulting hash / =row (the block takes array of hashes)
          # when chunking is not enabled, there is only one hash in each array
          MyModel.create( array.first )
    end

     => returns number of chunks / rows we processed

#### Example 4: Populate a MongoDB Database in Chunks of 100 records with SmarterCSV:

    # using chunks:
    filename = '/tmp/some.csv'
    options = {:chunk_size => 100, :key_mapping => {:unwanted_row => nil, :old_row_name => :new_name}}
    n = SmarterCSV.process(filename, options) do |chunk|
          # we're passing a block in, to process each resulting hash / row (block takes array of hashes)
          # when chunking is enabled, there are up to :chunk_size hashes in each chunk
          MyModel.collection.insert( chunk )   # insert up to 100 records at a time
    end

     => returns number of chunks we processed


#### Example 5: Reading a CSV-like File, and Processing it with Resque:

    filename = '/tmp/strange_db_dump'   # a file with CRTL-A as col_separator, and with CTRL-B\n as record_separator (hello iTunes!)
    options = {
      :col_sep => "\cA", :row_sep => "\cB\n", :comment_regexp => /^#/,
      :chunk_size => 100 , :key_mapping => {:export_date => nil, :name => :genre}
    }
    n = SmarterCSV.process(filename, options) do |chunk|
        Resque.enque( ResqueWorkerClass, chunk ) # pass chunks of CSV-data to Resque workers for parallel processing
    end
    => returns number of chunks

#### Example 6: Using Value Converters

NOTE: If you use `key_mappings` and `value_converters`, make sure that the value converters has references the keys based on the final mapped name, not the original name in the CSV file.

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
     | :comment_regexp             |   /^#/   | regular expression which matches comment lines (see NOTE about the CSV header)       |
     ---------------------------------------------------------------------------------------------------------------------------------
     | :col_sep                    |   ','    | column separator                                                                     |
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
     | :user_provided_headers      |   nil    | *careful with that axe!*                                                             |
     |                             |          | user provided Array of header strings or symbols, to define                          |
     |                             |          | what headers should be used, overriding any in-file headers.                         |
     |                             |          | You can not combine the :user_provided_headers and :key_mapping options              |
     | :remove_empty_hashes        |   true   | remove / ignore any hashes which don't have any key/value pairs                      |
     | :verbose                    |   false  | print out line number while processing (to track down problems in input files)       |
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
     | :remove_zero_values         |   true   | remove values which have a numeric value equal to zero / 0                           |
     | :remove_values_matching     |   nil    | removes key/value pairs if value matches given regular expressions. e.g.:            |
     |                             |          | /^\$0\.0+$/ to match $0.00 , or /^#VALUE!$/ to match errors in Excel spreadsheets    |
     | :convert_values_to_numeric  |   true   | converts strings containing Integers or Floats to the appropriate class              |
     |                             |          |      also accepts either {:except => [:key1,:key2]} or {:only => :key3}              |
     ---------------------------------------------------------------------------------------------------------------------------------


#### NOTES about File Encodings:
 * if you have a CSV file which contains unicode characters, you can process it as follows:


       File.open(filename, "r:bom|utf-8") do |f|
         data = SmarterCSV.process(f);
       end

* if the CSV file with unicode characters is in a remote location, similarly you need to give the encoding as an option to the `open` call:

       require 'open-uri'
       file_location = 'http://your.remote.org/sample.csv'
       open(file_location, 'r:utf-8') do |f|   # don't forget to specify the UTF-8 encoding!!
         data = SmarterCSV.process(f)
       end

#### NOTES about CSV Headers:
 * as this method parses CSV files, it is assumed that the first line of any file will contain a valid header
 * the first line with the CSV header may or may not be commented out according to the :comment_regexp
 * any occurences of :comment_regexp or :row_sep will be stripped from the first line with the CSV header
 * any of the keys in the header line will be downcased, spaces replaced by underscore, and converted to Ruby symbols before being used as keys in the returned Hashes
 * you can not combine the :user_provided_headers and :key_mapping options
 * if the incorrect number of headers are provided via :user_provided_headers, exception SmarterCSV::HeaderSizeMismatch is raised

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

    gem 'smarter_csv'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install smarter_csv

## Upcoming

Planned in the next releases:
 * programmatic header transformations
 * CSV command line

## Changes

#### 1.2.3 (2018-01-27)
 * fixed regression / test
 * fuxed quote_char interpolation for headers, but not data (thanks to Colin Petruno)

#### 1.2.1 (2018-01-25)    ### YANKED!
 * bugfix (thanks to Joshua Smith for reporting)

#### 1.2.0 (2018-01-20)
 * add default validation that a header can only appear once
 * add option `required_headers`

#### 1.1.5 (2017-11-05)
 * fix issue with invalid byte sequences in header (issue #103, thanks to Dave Myron)
 * fix issue with invalid byte sequences in multi-line data (thanks to Ivan Ushakov)
 * analyze only 500 characters by default when `:row_sep => :auto` is used.
   added option `row_sep_auto_chars` to change the default if necessary. (thanks to Matthieu Paret)

#### 1.1.4 (2017-01-16)
 * fixing UTF-8 related bug which was introduced in 1.1.2 (thanks to Tirdad C.)

#### 1.1.3 (2016-12-30)
 * added warning when options indicate UTF-8 processing, but input filehandle is not opened with r:UTF-8 option

#### 1.1.2 (2016-12-29)
 * added option `invalid_byte_sequence` (thanks to polycarpou)
 * added comments on handling of UTF-8 encoding when opening from File vs. OpenURI (thanks to KevinColemanInc)

#### 1.1.1 (2016-11-26)
 * added option to `skip_lines` (thanks to wal)
 * added option to `force_utf8` encoding (thanks to jordangraft)
 * bugfix if no headers in input data (thanks to esBeee)
 * ensure input file is closed (thanks to waldyr)
 * improved verbose output (thankd to benmaher)
 * improved documentation

#### 1.1.0 (2015-07-26)
 * added feature :value_converters, which allows parsing of dates, money, and other things (thanks to Raphaël Bleuse, Lucas Camargo de Almeida, Alejandro)
 * added error if :headers_in_file is set to false, and no :user_provided_headers are given (thanks to innhyu)
 * added support to convert dashes to underscore characters in headers (thanks to César Camacho)
 * fixing automatic detection of \r\n line-endings (thanks to feens)

#### 1.0.19 (2014-10-29)
 * added option :keep_original_headers to keep CSV-headers as-is (thanks to Benjamin Thouret)

#### 1.0.18 (2014-10-27)
 * added support for multi-line fields / csv fields containing CR (thanks to Chris Hilton) (issue #31)

#### 1.0.17 (2014-01-13)
 * added option to set :row_sep to :auto , for automatic detection of the row-separator (issue #22)

#### 1.0.16 (2014-01-13)
 * :convert_values_to_numeric option can now be qualified with :except or :only (thanks to Hugo Lepetit)
 * removed deprecated `process_csv` method

#### 1.0.15 (2013-12-07)
 * new option:
   * :remove_unmapped_keys  to completely ignore columns which were not mapped with :key_mapping (thanks to Dave Sanders)

#### 1.0.14 (2013-11-01)
 * added GPL-2 and MIT license to GEM spec file; if you need another license contact me

#### 1.0.13 (2013-11-01)    ### YANKED!
 * added GPL-2 license to GEM spec file; if you need another license contact me

#### 1.0.12 (2013-10-15)
 * added RSpec tests

#### 1.0.11 (2013-09-28)
 * bugfix : fixed issue #18 - fixing issue with last chunk not being properly returned (thanks to Jordan Running)
 * added RSpec tests

#### 1.0.10 (2013-06-26)
 * bugfix : fixed issue #14 - passing options along to CSV.parse (thanks to Marcos Zimmermann)

#### 1.0.9 (2013-06-19)
 * bugfix : fixed issue #13 with negative integers and floats not being correctly converted (thanks to Graham Wetzler)

#### 1.0.8 (2013-06-01)

 * bugfix : fixed issue with nil values in inputs with quote-char (thanks to Félix Bellanger)
 * new options:
    * :force_simple_split : to force simiple splitting on :col_sep character for non-standard CSV-files. e.g. without properly escaped :quote_char
    * :verbose : print out line number while processing (to track down problems in input files)

#### 1.0.7 (2013-05-20)

 * allowing process to work with objects with a 'readline' method (thanks to taq)
 * added options:
    * :file_encoding : defaults to utf8  (thanks to MrTin, Paxa)

#### 1.0.6 (2013-05-19)

 * bugfix : quoted fields are now correctly parsed

#### 1.0.5 (2013-05-08)

 * bugfix : for :headers_in_file option

#### 1.0.4 (2012-08-17)

 * renamed the following options:
    * :strip_whitepace_from_values => :strip_whitespace   - removes leading/trailing whitespace from headers and values

#### 1.0.3 (2012-08-16)

 * added the following options:
    * :strip_whitepace_from_values   - removes leading/trailing whitespace from values

#### 1.0.2 (2012-08-02)

 * added more options for dealing with headers:
    * :user_provided_headers ,user provided Array with header strings or symbols, to precisely define what the headers should be, overriding any in-file headers (default: nil)
    * :headers_in_file , if the file contains headers as the first line (default: true)

#### 1.0.1 (2012-07-30)

 * added the following options:
    * :downcase_header
    * :strings_as_keys
    * :remove_zero_values
    * :remove_values_matching
    * :remove_empty_hashes
    * :convert_values_to_numeric

 * renamed the following options:
    * :remove_empty_fields => :remove_empty_values


#### 1.0.0 (2012-07-29)

 * renamed `SmarterCSV.process_csv` to `SmarterCSV.process`.

#### 1.0.0.pre1 (2012-07-29)


## Reporting Bugs / Feature Requests

Please [open an Issue on GitHub](https://github.com/tilo/smarter_csv/issues) if you have feedback, new feature requests, or want to report a bug. Thank you!


## Special Thanks

Many thanks to people who have filed issues and sent comments.
And a special thanks to those who contributed pull requests:

 * [Jack 0](https://github.com/xjlin0)
 * [Alejandro](https://github.com/agaviria)
 * [Lucas Camargo de Almeida](https://github.com/lcalmeida)
 * [Raphaël Bleuse](https://github.com/bleuse)
 * [feens](https://github.com/feens)
 * [César Camacho](https://github.com/chanko)
 * [innhyu](https://github.com/innhyu)
 * [Benjamin Thouret](https://github.com/benichu)
 * [Chris Hilton](https://github.com/chrismhilton)
 * [Sean Duckett](http://github.com/sduckett)
 * [Alex Ong](http://github.com/khaong)
 * [Martin Nilsson](http://github.com/MrTin)
 * [Eustáquio Rangel](http://github.com/taq)
 * [Pavel](http://github.com/paxa)
 * [Félix Bellanger](https://github.com/Keeguon)
 * [Graham Wetzler](https://github.com/grahamwetzler)
 * [Marcos G. Zimmermann](https://github.com/marcosgz)
 * [Jordan Running](https://github.com/jrunning)
 * [Dave Sanders](https://github.com/DaveSanders)
 * [Hugo Lepetit](https://github.com/giglemad)
 * [esBeee](https://github.com/esBeee)
 * [Waldyr de Souza](https://github.com/waldyr)
 * [Ben Maher](https://github.com/benmaher)
 * [Wal McConnell](https://github.com/wal)
 * [Jordan Graft](https://github.com/jordangraft)
 * [Michael](https://github.com/polycarpou)
 * [Kevin Coleman](https://github.com/KevinColemanInc)
 * [Tirdad C.](https://github.com/tridadc)
 * [Dave Myron](https://github.com/contentfree)
 * [Ivan Ushakov](https://github.com/IvanUshakov)
 * [Matthieu Paret](https://github.com/mtparet)
 * [Rohit Amarnath](https://github.com/ramarnat)
 * [Joshua Smith](https://github.com/enviable)
 * [Colin Petruno](https://github.com/colinpetruno)


## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Added some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request

