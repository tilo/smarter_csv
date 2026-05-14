
### Contents

  * [Introduction](./_introduction.md)
  * [Migrating from Ruby CSV](./migrating_from_csv.md)
  * [Ruby CSV Pitfalls](./ruby_csv_pitfalls.md)
  * [Parsing Strategy](./parsing_strategy.md)
  * [The Basic Read API](./basic_read_api.md)
  * [The Basic Write API](./basic_write_api.md)
  * [Batch Processing](././batch_processing.md)
  * [Configuration Options](./options.md)
  * [**Row and Column Separators**](./row_col_sep.md)
  * [Header Transformations](./header_transformations.md)
  * [Header Validations](./header_validations.md)
  * [Column Selection](./column_selection.md)
  * [Data Transformations](./data_transformations.md)
  * [Value Converters](./value_converters.md)
  * [Bad Row Quarantine](./bad_row_quarantine.md)
  * [Warnings](./warnings.md)
  * [Instrumentation Hooks](./instrumentation.md)
  * [Examples](./examples.md)
  * [Real-World CSV Files](./real_world_csv.md)
  * [SmarterCSV over the Years](./history.md)
  * [Release Notes](./releases/1.16.0/changes.md)

--------------

# Row and Column Separators

## Automatic Detection

Convenient defaults allow automatic detection of the column and row separators: `row_sep: :auto`, `col_sep: :auto`. This makes it easier to process any CSV files without having to examine the line endings or column separators, e.g. when users upload CSV files to your service and you have no control over the incoming files.

The setting `:auto_row_sep_chars` controls the initial scan size used while detecting the row separator (default is `4096`). Detection stops as soon as one separator has a clear majority, up to a 64KB cap. Bump it higher if your files have very wide headers or long comment preambles; out-of-range values, `nil`, or `0` fall back to the default with a warning. Of course you can also set the `:row_sep` manually to skip auto-detection entirely.


## Column Separator `col_sep`

The automatic detection of column separators considers: `,`, `\t`, `;`, `:`, `|`.

Some CSV files may contain an unusual column separqator, which could even be a control character.

### Tab-Separated Values (TSV)

Tab-separated files are auto-detected by default — no options needed:

```ruby
$ cat data.tsv
id<TAB>name<TAB>amount
1<TAB>Alice<TAB>100
2<TAB>Bob<TAB>200

# Auto-detected — col_sep: :auto is the default
SmarterCSV.process('data.tsv')

# Or set the separator explicitly
SmarterCSV.process('data.tsv', col_sep: "\t")
```

The default `col_sep: :auto` picks tab when it's the dominant delimiter in the first chunk of the file. The explicit form is useful in test fixtures or when you want to fail fast on unexpected formats.

## Row Separator `row_sep`

The automatic detection of row separators considers: `\n`, `\r\n`, `\r`.

Some CSV files may contain an unusual row separqator, which could even be a control character.


## Custom / Non-Standard CSV Formats

Besides custom values for `col_sep`, `row_sep`, some other customizations of CSV files are:
*  the presence of a number of leading lines before the header or data section start.
*  the presence of comment lines, e.g. lines starting with `#`

To explore these special cases, please use the following examples.

### Example 1: reading an iTunes DB dump

This data format uses CTRL-A as the column separator, and CTRL-B as the record separator. It also has comment lines that start with a `#` character. This also maps the header `name` to `genre`, and ignores the column `export_date`.

```ruby
    filename = '/tmp/itunes_db_dump'   
    options = {
      :col_sep => "\cA", :row_sep => "\cB", :comment_regexp => /^#/,
      :chunk_size => 100 , :key_mapping => {export_date: nil, name: :genre},
    }
    n = SmarterCSV.process(filename, options) do |chunk|
      SidekiqWorkerClass.process_async(chunk) # pass an array of hashes to Sidekiq workers for parallel processing
    end
    => returns number of chunks
```

### Example 2: Reading a CSV-File with custom col_sep, row_sep
In this example we have an unusual CSV file with `|` as the row separator, and `#` as the column separator.
This unusual format needs explicit options `col_sep` and `row_sep`.

```ruby
    filename = '/tmp/input_file.txt'
    recordsA = SmarterCSV.process(filename, {col_sep: "#", row_sep: "|"})

    => returns an array of hashes
```

### Example 3:
In this example, we use `skip_lines: 3` to skip and ignore the first 3 lines in the input


```ruby
    filename = '/tmp/input_file.txt'
    recordsA = SmarterCSV.process(filename, {skip_lines: 3})

    => returns an array of hashes
```
  

### Example 4: reading an iTunes DB dump

In this example, we use `comment_regexp` to filter out and ignore any lines starting with `#`


```ruby
    # Consider a file with CRTL-A as col_separator, and with CTRL-B\n as record_separator (hello iTunes!)
    filename = '/tmp/strange_db_dump'   
    options = {
      :col_sep => "\cA", :row_sep => "\cB", :comment_regexp => /^#/,
      :chunk_size => 100 , :key_mapping => {:export_date => nil, :name => :genre},
    }
    n = SmarterCSV.process(filename, options) do |chunk|
      SidekiqWorkerClass.process_async(chunk) # pass an array of hashes to Sidekiq workers for parallel processing
    end
    => returns number of chunks
```

----------------

PREVIOUS: [Configuration Options](./options.md) | NEXT: [Header Transformations](./header_transformations.md) | UP: [README](../README.md)
