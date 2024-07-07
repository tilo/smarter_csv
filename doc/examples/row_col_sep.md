
# Automatic Detection

SmarterCSV defaults to automatically detecting row and column separators based on the data in the given input, using the defaults `col_sep: :auto`, `row_sep: :auto`.

These options can be overridden. 

# Column Separator

The automatic detection of column separators considers: `',', "\t", ';', ':', '|'`.

Some CSV files may contain an unusual column separqator, which could even be a control character.

# Row Separator

The automatic detection of row separators considers: `\n`, `\r\n`, `\r`.

Some CSV files may contain an unusual row separqator, which could even be a control character.

# Examples
## Example 1: reading an iTunes DB dump

```ruby
    # Consider a file with CRTL-A as col_separator, and with CTRL-B\n as record_separator (hello iTunes!)
    filename = '/tmp/strange_db_dump'   
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

```ruby
    filename = '/tmp/input_file.txt'
    recordsA = SmarterCSV.process(filename, {:col_sep => "#", :row_sep => "|"})

    => returns an array of hashes
```
