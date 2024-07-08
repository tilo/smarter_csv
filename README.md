
# SmarterCSV

 [![codecov](https://codecov.io/gh/tilo/smarter_csv/branch/main/graph/badge.svg?token=1L7OD80182)](https://codecov.io/gh/tilo/smarter_csv) [![Gem Version](https://badge.fury.io/rb/smarter_csv.svg)](http://badge.fury.io/rb/smarter_csv)

 SmarterCSV provides a convenient interface for reading and writing CSV files and data.

 Unlike traditional CSV parsing methods, SmarterCSV focuses on representing the data for each row as a Ruby hash, which lends itself perfectly for direct use with ActiveRecord, Sidekiq, and JSON stores such as S3. For large files it supports processing CSV data in chunks of array-of-hashes, which allows parallel or batch processing of the data.

 Its powerful interface is designed to simplify and optimize the process of handling CSV data, and allows for highly customizable and efficient data processing by enabling the user to easily map CSV headers to Hash keys, skip unwanted rows, and transform data on-the-fly. 

 This results in a more readable, maintainable, and performant codebase. Whether you're dealing with large datasets or complex data transformations, SmarterCSV streamlines CSV operations, making it an invaluable tool for developers seeking to enhance their data processing workflows.

  When writing CSV data to file, it similarly takes arrays of hashes, and converts them to a CSV file.

One user wrote:

  > *Best gem for CSV for us yet. [...] taking an import process from 7+ hours to about 3 minutes. [...] Smarter CSV was a big part and helped clean up our code ALOT*

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

# Documentation

  * [Introduction](docs/_introduction.md)
  * [The Basic API](docs/basic_api.md)
  * [Batch Processing](./docs/batch_processing.md)
  * [Configuration Options](docs/options.md)
  * [Row and Column Separators](docs/row_col_sep.md)
  * [Header Transformations](docs/header_transformations.md)
  * [Header Validations](docs/header_validations.md)
  * [Data Transformations](docs/data_transformations.md)
  * [Value Converters](docs/value_converters.md)
    
# Articles
* [Parsing CSV Files in Ruby with SmarterCSV](https://tilo-sloboda.medium.com/parsing-csv-files-in-ruby-with-smartercsv-6ce66fb6cf38)
* [Processing 1.4 Million CSV Records in Ruby, fast ](https://lcx.wien/blog/processing-14-million-csv-records-in-ruby/)
* [Speeding up CSV parsing with parallel processing](http://xjlin0.github.io/tech/2015/05/25/faster-parsing-csv-with-parallel-processing)
* [The original post](http://www.unixgods.org/Ruby/process_csv_as_hashes.html) that started SmarterCSV

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

