# SmarterCSV 2


[![Build Status](https://secure.travis-ci.org/tilo/smarter_csv.svg?branch=2.0-develop)](http://travis-ci.org/tilo/smarter_csv)
[![Gem Version](https://badge.fury.io/rb/smarter_csv.svg)](http://badge.fury.io/rb/smarter_csv)


---------------
#### Service Announcement

**SmarterCSV 2.0.0.pre1 is out soon! 🎉 You are looking at the 2.x documentation.**

If you are looking for SmarterCSV 1.x, please check the [README on the `1.x-stable` branch](https://github.com/tilo/smarter_csv/tree/1.x-stable).

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

## [Change Log](CHANGELOG.md)

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
 * [Diego Salido](https://github.com/salidux)


## Reporting Issues

1. Please provide the gem version, a sample CSV file and code which reproduces the issue.
2. Please make a Pull Request with an RSpec3 test which demonstrates the bug if you can.

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Added some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request

