# SmarterCSV 2


[![Build Status](https://secure.travis-ci.org/tilo/smarter_csv.svg?branch=2.0-develop)](http://travis-ci.org/tilo/smarter_csv)
[![Gem Version](https://badge.fury.io/rb/smarter_csv.svg)](http://badge.fury.io/rb/smarter_csv)


---------------
#### Service Announcement

**SmarterCSV 2.0.0.pre1 is out soon! 🎉 You are looking at the 2.x documentation.**

If you are looking for SmarterCSV 1.x, please check the [README on the `1.2-stable` branch](https://github.com/tilo/smarter_csv/tree/1.2-stable).

For feature requests, feedback, comments on 2.x please open a GitHub comment.

---------------
#### SmarterCSV

Simple, efficient CSV processing for Ruby.

SmarterCSV is a Ruby Gem for smarter importing of CSV Files as Array(s) of Hashes, suitable for parallel processing with Resque or Sidekiq,
as well as direct processing with ActiveRecord, Mongoiid.

One SmarterCSV user wrote:

  *Best gem for CSV for us yet. [...] taking an import process from 7+ hours to about 3 minutes.
   [...] SmarterCSV was a big part and helped clean up our code ALOT*

SmarterCSV was designed with the use cases in mind that you want to use the imported data to either update a database record, or pass the data on to a background worker.


### Requirements

SmarterCSV supports Ruby >= 2.2, and is not tied to a specific Rails version.
Please take note that Ruby 2.2 EOL date is scheduled for 2018-03-31

### Installation


      gem install smarter_csv


### [Docs and Examples are on the Wiki](https://github.com/tilo/smarter_csv/wiki)

Find the examples and documentation please check the [Wiki pages](https://github.com/tilo/smarter_csv/wiki)


### Features

Now SmarterCSV 2.0 is out, and strives to keep the same features, but using a different implementation which allows you more control when you need to handle special cases.
Becaues of this, some of the options from version 1.x are no longer supported. Alternative solutions can be found in the Upgrading guide.

SmarterCSV 2.x has lots of features:

 * able to process large CSV-files
 * able to chunk the input from the CSV file to avoid loading the whole CSV file into memory
 * return a Hash for each line of the CSV file, so we can quickly use the results for either creating MongoDB or ActiveRecord entries, or further processing with Resque
 * able to pass a block to the `process` method, so data from the CSV file can be directly processed (e.g. Resque.enqueue )
 * allows to have a bit more flexible input format, where comments are possible, and col_sep,row_sep can be set to any character sequence, including control characters.

 * able to transmogrify CSV column names to the Hash keys of your choice (see: header_transformations)
 * able to ignore unwanted CSV columns and exclude them from the resulting hash (just map them to `nil`)
 * able to do header validations, based on the resulting keys computed from CSV column names (see: header_validations)
 * able to do data transformations (these apply for all data in a row)
 * able to do hash_transformations (based on the final key/value pairs in the hash)
 * able to do hash validations (which can surface the errors per line)

 * able to eliminate key/value pairs with blank, or `nil` values from the result hashes.
 * you can use the transformations to implement any custom behavior by passing-in one or more `Proc`s.

NOTE; This Gem is only for importing CSV files - writing of CSV files is not supported at this time, but writing is on the feature list for the future..+


#### Default Behavior vs Customization


SmarterCSV was designed with the use cases in mind that you want to use the imported data to either update a database record, or pass the data on to a background worker.
It's default behavior is to change the headers of a CSV file into symbols, which are then used in a hash that gets constructed for each line of the CSV file.
This default behavior can be changed and customized.


### Why?

Ruby's CSV library's API is pretty old, and it's processing of CSV-files returning Arrays of Arrays feels 'very close to the metal'. The output is not easy to use - especially not if you want to create database records from it. Another shortcoming is that Ruby's CSV library does not have good support for huge CSV-files, e.g. there is no support for 'chunking' and/or parallel processing of the CSV-content (e.g. with Resque or Sidekiq),

As the existing CSV libraries didn't fit my needs, I was writing my own CSV processing - specifically for use in connection with Rails ORMs like Mongoid, MongoMapper or ActiveRecord. In those ORMs you can easily pass a hash with attribute/value pairs to the create() method. The lower-level Mongo driver and Moped also accept larger arrays of such hashes to create a larger amount of records quickly with just one call.

## Parallel Processing
[Jack](https://github.com/xjlin0) wrote an interesting article about [Speeding up CSV parsing with parallel processing](http://xjlin0.github.io/tech/2015/05/25/faster-parsing-csv-with-parallel-processing)

[Tyler Tringas](https://github.com/ttringas) wrote an awesome article about [Very large CSV import in Rails on Heroku](https://tylertringas.com/very-large-csv-import-in-rails-on-heroku/)

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

#### 2.0.0.pre1 (to be released soon!)
 * completely overhauled how headers and data lines are processed - users can now write their own Procs to transmogrify the raw data.
 * adding validations, so you can catch errors while or after processing a CSV file.

#### 1.2.3 (2018-01-27)
* fixed regression / test
* fixed quote_char interpolation for headers, but not data (thanks to Colin Petruno)
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
 * [Chris Wong](https://github.com/lightwave)
 * [Olle Jonsson](https://github.com/olleolleolle)
 * [Nicolas Guillemain](https://github.com/Viiruus)
 * [Sp6](https://github.com/sp6)


## Reporting Issues

1. Please provide the gem version, a sample CSV file and code which reproduces the issue.
2. Please make a Pull Request with an RSpec3 test which demonstrates the bug if you can.

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Added some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request

