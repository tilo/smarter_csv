
# Automatic Detection

Convenient defaults allow automatic detection of the column and row separators: `row_sep: :auto`, `col_sep: :auto`. This makes it easier to process any CSV files without having to examine the line endings or column separators, e.g. when users upload CSV files to your service and you have no control over the incoming files.

You can change the setting `:auto_row_sep_chars` to only analyze the first N characters of the file (default is 500 characters); `nil` or `0` will check the whole file). Of course you can also set the `:row_sep` manually.


# Column Separator

The automatic detection of column separators considers: `',', "\t", ';', ':', '|'`.

Some CSV files may contain an unusual column separqator, which could even be a control character.

# Row Separator

The automatic detection of row separators considers: `\n`, `\r\n`, `\r`.

Some CSV files may contain an unusual row separqator, which could even be a control character.

# Examples
## Example 1: reading an iTunes DB dump

This data format uses CTRL-A as the column separator, and CTRL-B as the record separator. It also has comment lines that start with a `#` character.

```ruby
    filename = '/tmp/itunes_db_dump'   
    options = {
      :col_sep => "\cA", :row_sep => "\cB\n", :comment_regexp => /^#/,
      :chunk_size => 100 , :key_mapping => {:export_date => nil, :name => :genre},
    }
    n = SmarterCSV.process(filename, options) do |chunk|
      SidekiqWorkerClass.process_async(chunk) # pass an array of hashes to Sidekiq workers for parallel processing
    end
    => returns number of chunks
```

## Example 2: Reading a CSV-File with custom col_sep, row_sep
In this example we have an unusual CSV file with `|` as the row separator, and `#` as the column separator.
This unusual format needs explicit options `col_sep` and `row_sep`.

```ruby
    filename = '/tmp/input_file.txt'
    recordsA = SmarterCSV.process(filename, {:col_sep => "#", :row_sep => "|"})

    => returns an array of hashes
```
