
# SmarterCSV

  ![Gem Version](https://img.shields.io/gem/v/smarter_csv) [![codecov](https://codecov.io/gh/tilo/smarter_csv/branch/main/graph/badge.svg?token=1L7OD80182)](https://codecov.io/gh/tilo/smarter_csv) [View on RubyGems](https://rubygems.org/gems/smarter_csv) [View on RubyToolbox](https://www.ruby-toolbox.com/search?q=smarter_csv)

 SmarterCSV provides a convenient interface for reading and writing CSV files and data.

 Unlike traditional CSV parsing methods, SmarterCSV focuses on representing the data for each row as a Ruby hash, which lends itself perfectly for direct use with ActiveRecord, Sidekiq, and JSON stores such as S3. For large files it supports processing CSV data in chunks of array-of-hashes, which allows parallel or batch processing of the data.

 Its powerful interface is designed to simplify and optimize the process of handling CSV data, and allows for highly customizable and efficient data processing by enabling the user to easily map CSV headers to Hash keys, skip unwanted rows, and transform data on-the-fly. 

 This results in a more readable, maintainable, and performant codebase. Whether you're dealing with large datasets or complex data transformations, SmarterCSV streamlines CSV operations, making it an invaluable tool for developers seeking to enhance their data processing workflows.

  When writing CSV data to file, it similarly takes arrays of hashes, and converts them to a CSV file.

One user wrote:

  > *Best gem for CSV for us yet. [...] taking an import process from 7+ hours to about 3 minutes. [...] Smarter CSV was a big part and helped clean up our code ALOT*

## Performance

SmarterCSV is designed for **real-world CSV processing**, returning fully usable hashes with symbol keys and type conversions — not raw arrays that require additional post-processing.

**Beware of benchmarks that only measure raw CSV parsing.** Such comparisons measure tokenization alone, while real-world usage requires hash construction, key normalization, type conversion, and edge-case handling. Omitting this work **understates the actual cost of CSV ingestion**.

For a fair comparison, `CSV.table` is the closest Ruby CSV equivalent to SmarterCSV.

| Comparison            | P90         | Range             |
|-----------------------|-------------|-------------------|
| vs SmarterCSV 1.14.4  | ~11× faster | 5× to 28× faster |
| vs CSV.table          | ~22× faster | 6× to 82× faster |
| vs CSV hashes         |  ~8× faster | 2× to 25× faster |

The P90 numbers are without the extremely positive best cases, which would yield a P90 of ~25×, ~75×, ~25× respectively.

SmarterCSV also wins 13 of 16 benchmark files head-to-head against ZSV+wrapper (SIMD-accelerated C parser with Ruby wrapper to produce equivalent hash output).

_Benchmarks: 16 CSV files (43k–80k rows), Ruby 3.4.7, Apple M1. Memory: 39% less allocated, 43% fewer objects. See [CHANGELOG](./CHANGELOG.md) and [PR #319](https://github.com/tilo/smarter_csv/pull/319) for details._

## Examples

### Simple Example:

SmarterCSV is designed for robustness — real-world CSV data often has inconsistent formatting, extra whitespace, and varied column separators. Its intelligent defaults automatically clean and normalize data, returning high-quality hashes ready for direct use with ActiveRecord, Sidekiq, or any data pipeline — no post-processing required. See [Parsing CSV Files in Ruby with SmarterCSV](https://tilo-sloboda.medium.com/parsing-csv-files-in-ruby-with-smartercsv-6ce66fb6cf38) for more background.

```ruby
$ cat spec/fixtures/sample.csv
   First Name  , Last	 Name , Emoji , Posts
José ,Corüazón, ❤️, 12
Jürgen, Müller ,😐,3
 Michael, May ,😞, 7

$ irb
>> require 'smarter_csv'
=> true
>> data = SmarterCSV.process('spec/fixtures/sample.csv')
=> [{:first_name=>"José", :last_name=>"Corüazón", :emoji=>"❤️", :posts=>12},
    {:first_name=>"Jürgen", :last_name=>"Müller", :emoji=>"😐", :posts=>3},
    {:first_name=>"Michael", :last_name=>"May", :emoji=>"😞", :posts=>7}]
```
Notice how SmarterCSV automatically (all defaults):
- Normalizes headers → `downcase_header: true`, `strings_as_keys: false`
- Strips whitespace → `strip_whitespace: true`
- Converts numbers → `convert_values_to_numeric: true`
- Removes empty values → `remove_empty_values: true`
- Preserves Unicode and emoji characters

### Batch Processing:

Processing large CSV files in chunks minimizes memory usage and enables powerful workflows:
- **Database imports** — bulk insert records in batches for better performance
- **Parallel processing** — distribute chunks across Sidekiq, Resque, or other background workers
- **Progress tracking** — the optional `chunk_index` parameter enables progress reporting
- **Memory efficiency** — only one chunk is held in memory at a time, regardless of file size

The block receives a `chunk` (array of hashes) and an optional `chunk_index` (0-based sequence number):

```ruby
# Database bulk import
SmarterCSV.process(filename, chunk_size: 100) do |chunk, chunk_index|
  puts "Processing chunk #{chunk_index}..."
  MyModel.insert_all(chunk)  # chunk is an array of hashes
end

# Parallel processing with Sidekiq
SmarterCSV.process(filename, chunk_size: 100) do |chunk|
  MyWorker.perform_async(chunk)  # each chunk processed in parallel
end
```

See [Examples](docs/examples.md), [Batch Processing](docs/batch_processing.md), and [Configuration Options](docs/options.md) for more.

## Requirements

**Minimum Ruby Version:** >= 2.6

**C Extension:** SmarterCSV includes a native C extension for accelerated CSV parsing.
The C extension is automatically compiled on MRI Ruby. For JRuby and TruffleRuby, SmarterCSV falls back to a pure Ruby implementation.

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
  * [Parsing Strategy](docs/parsing_strategy.md)
  * [The Basic Read API](docs/basic_read_api.md)
  * [The Basic Write API](docs/basic_write_api.md)
  * [Batch Processing](./docs/batch_processing.md)
  * [Configuration Options](docs/options.md)
  * [Row and Column Separators](docs/row_col_sep.md)
  * [Header Transformations](docs/header_transformations.md)
  * [Header Validations](docs/header_validations.md)
  * [Data Transformations](docs/data_transformations.md)
  * [Value Converters](docs/value_converters.md)
    
# Articles
  * [Parsing CSV Files in Ruby with SmarterCSV](https://tilo-sloboda.medium.com/parsing-csv-files-in-ruby-with-smartercsv-6ce66fb6cf38)
  * [CSV Writing with SmarterCSV](https://tilo-sloboda.medium.com/csv-writing-with-smartercsv-26136d47ad0c)
  * [Processing 1.4 Million CSV Records in Ruby, fast ](https://lcx.wien/blog/processing-14-million-csv-records-in-ruby/)
  * [Faster Parsing CSV with Parallel Processing](http://xjlin0.github.io/tech/2015/05/25/faster-parsing-csv-with-parallel-processing) by [Jack lin](https://github.com/xjlin0/)
  * The original [Stackoverflow Question](https://stackoverflow.com/questions/7788618/update-mongodb-with-array-from-csv-join-table/7788746#7788746) that inspired SmarterCSV
  * [The original post](http://www.unixgods.org/Ruby/process_csv_as_hashes.html) for SmarterCSV

# [ChangeLog](./CHANGELOG.md)

# Reporting Bugs / Feature Requests

Please [open an Issue on GitHub](https://github.com/tilo/smarter_csv/issues) if you have feedback, new feature requests, or want to report a bug. Thank you!

For reporting issues, please:
  * include a small sample CSV file
  * open a pull-request adding a test that demonstrates the issue
  * mention your version of SmarterCSV, Ruby, Rails

# [A Special Thanks to all 59 Contributors!](CONTRIBUTORS.md) 🎉🎉🎉


# Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Added some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request

