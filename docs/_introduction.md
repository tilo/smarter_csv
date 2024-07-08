
### Contents

  * [**Introduction**](./_introduction.md)
  * [The Basic API](./basic_api.md)
  * [Batch Processing](././batch_processing.md)
  * [Configuration Options](./options.md)
  * [Row and Column Separators](./row_col_sep.md)
  * [Header Transformations](./header_transformations.md)
  * [Header Validations](./header_validations.md)
  * [Data Transformations](./data_transformations.md)
  * [Value Converters](./value_converters.md)
    
--------------  

# SmarterCSV Introduction

`smarter_csv` is a Ruby Gem for convenient reading and writing of CSV files. It has intelligent defaults, and auto-discovery of column and row separators. It imports CSV Files as Array(s) of Hashes, suitable for direct processing with ActiveRecord, kicking-off batch jobs with Sidekiq, parallel processing, or oploading data to S3. Similarly, writing CSV files takes Hashes, or Arrays of Hashes to create a CSV file.

## Why another CSV library?

Ruby's original 'csv' library's API is pretty old, and its processing of CSV-files returning an array-of-array format feels unnecessarily 'close to the metal'. Its output is not easy to use - especially not if you need a data hash to create database records, or JSON from it, or pass it to Sidekiq or S3. Another shortcoming is that Ruby's 'csv' library does not have good support for huge CSV-files, e.g. there is no support for batching and/or parallel processing of the CSV-content (e.g. with Sidekiq jobs).

When SmarterCSV was envisioned, I needed to do nightly imports of very large data sets that came in CSV format, that needed to be upserted into a database, and because of the sheer volume of data needed to be processed in parallel.
The CSV processing also needed to be robust against variations in the input data.

## Benefits of using SmarterCSV

* Improved Robustness: 
  Typically you have little control over the data quality of CSV files that need to be imported. Because SmarterCSV has intelligent defaults and auto-detection of typical formats, this improves the robustness of your CSV imports without having to manually tweak options.

* Easy-to-use Format:
  By using a Ruby hash to represent a CSV row, SmarterCSV allows you to directly use this data and insert it into a database, or use it with Sidekiq, S3, message queues, etc

* Normalized Headers:
  SmarterCSV automatically transforms CSV headers to Ruby symbols, stripping leading or trailing whitespace.
  There are many ways to customize the header transformation to your liking. You can re-map CSV headers to hash keys, and you can ignore CSV columns.

* Normalized Data:
  SmarterCSV transforms the data in each CSV row automatically, stripping whitespace, converting numerical data into numbers, ignoring nil or empty fields, and more. There are many ways to customize this. You can even add your own value converters.

* Batch Processing of large CSV files:
  Processing large CSV files in chunks, reduces the memory impact and allows for faster / parallel processing.
  By adding the option `chunk_size: numeric_value`, you can switch to batch processing. SmarterCSV will then return arrays-of-hashes. This makes parallel processing easy: you can pass whole chunks of data to Sidekiq, bulk-insert into a DB, or pass it to other data sinks.

## Additional Features

* Header Validation:
  You can validate that a set of hash keys is present in each record after header transformations are applied.
  This can help ensure importing data with consistent quality.

* Data Validations
  (planned feature)

---------------
PREVIOUS [README](../README.md) | NEXT: [The Basic API](./basic_api.md)
