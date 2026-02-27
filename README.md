
# SmarterCSV

  ![Gem Version](https://img.shields.io/gem/v/smarter_csv) [![codecov](https://codecov.io/gh/tilo/smarter_csv/branch/main/graph/badge.svg?token=1L7OD80182)](https://codecov.io/gh/tilo/smarter_csv) [View on RubyGems](https://rubygems.org/gems/smarter_csv) [View on RubyToolbox](https://www.ruby-toolbox.com/search?q=smarter_csv)

  SmarterCSV is a high-performance CSV reader and writer for Ruby focused on fastest end-to-end CSV ingestion — not just parsing.

  Beyond raw speed, SmarterCSV is designed to provide a significantly more convenient and developer-friendly interface than traditional CSV libraries. Instead of returning raw arrays that require substantial post-processing, SmarterCSV produces Rails-ready hashes for each row, making the data immediately usable with ActiveRecord, Sidekiq pipelines, parallel processing, and JSON-based workflows such as S3.

  The library includes intelligent defaults, automatic detection of column and row separators, and flexible header/value transformations. These features eliminate much of the boilerplate typically required when working with CSV data and help keep ingestion code concise and maintainable.

  For large files, SmarterCSV supports both chunked processing (arrays of hashes) and streaming via Enumerable APIs, enabling efficient batch jobs and low-memory pipelines. The C acceleration further optimizes the full ingestion path — including parsing, hash construction, and conversions — so performance gains reflect real-world workloads, not just tokenizer benchmarks.

  The interface is intentionally designed to robustly handle messy real-world CSV while keeping application code clean. Developers can easily map headers, skip unwanted rows, quarantine problematic data, and transform values on the fly without building custom post-processing pipelines.

  When exporting data, SmarterCSV converts arrays of hashes back into properly formatted CSV, maintaining the same focus on convenience and correctness.

**User Testimonial:**
  > “Best gem for CSV for us yet. […] taking an import process from 7+ hours to about 3 minutes. […] SmarterCSV was a big part and helped clean up our code A LOT.”


## Performance

SmarterCSV is designed for **real-world CSV processing**, returning fully usable hashes with symbol keys and type conversions — not raw arrays that require additional post-processing.

**Beware of benchmarks that only measure raw CSV parsing.** Such comparisons measure tokenization alone, while real-world usage requires hash construction, key normalization, type conversion, and edge-case handling. Omitting this work **understates the actual cost of CSV ingestion**.

For a fair comparison, `CSV.table` is the closest Ruby CSV equivalent to SmarterCSV.

| Comparison (SmarterCSV 1.16.0, C-accelerated)  | Range                   |
|-------------------------------------------------|-------------------------|
| vs SmarterCSV 1.14.4 (with C acceleration)      | 9.4× to 63.6× faster   |
| vs SmarterCSV 1.14.4 (Ruby path)                | 1.7× to 10.6× faster   |
| vs CSV.read  (arrays of arrays)                 | 1.8× to 7.5× faster    |
| vs CSV.table (arrays of hashes)                 | 6.4× to 118.7× faster  |
| vs ZSV (arrays of hashes, equiv. output)        | 1.1× to 6.6× faster †  |

† SmarterCSV faster on 15 of 16 files. ZSV raw arrays (no hashes, no conversions) are 2×–14× faster — but that omits the post-processing work needed to produce usable output.

_Benchmarks: 16 CSV files (43k–80k rows), Ruby 3.4.7, Apple M1. Memory: 39% less allocated, 43% fewer objects._

See [SmarterCSV 1.15.2: Faster Than Raw CSV Arrays](https://tilo-sloboda.medium.com/smartercsv-1-15-2-faster-than-raw-csv-arrays-benchmarks-zsv-and-the-full-pipeline-2c12a798032e) and [PR #319](https://github.com/tilo/smarter_csv/pull/319) for more details.


## Switching from Ruby CSV?

It's a one-line change:

```ruby
# Before
rows = CSV.table('data.csv').map(&:to_h)

# After — up to 119× faster, same symbol keys
rows = SmarterCSV.process('data.csv')
```

`SmarterCSV.parse(string)` works like `CSV.parse(string, headers: true, header_converters: :symbol)` — with numeric conversion included by default.

See [**Migrating from Ruby CSV**](docs/migrating_from_csv.md) for a full comparison of options, behavior differences, and a quick-reference table.

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
  * [**Migrating from Ruby CSV**](docs/migrating_from_csv.md)
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
  * [SmarterCSV over the Years](docs/history.md) — version timeline and performance journey (11×–119× faster than v1.6.1)

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

