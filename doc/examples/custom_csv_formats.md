# Custom / Non-Standard CSV Formats

Besides custom values for `col_sep`, `row_sep`, some other customizations of CSV files are:
*  the presence of a number of leading lines before the header or data section start.
*  the presence of comment lines, e.g. lines starting with `#`

To handle these special cases, please use the following options.


## Example 1:
In this example, we use `skip_lines: 3` to skip and ignore the first 3 lines in the input



  

## Example 2: reading an iTunes DB dump

In this example, we use `comment_regexp` to filter out and ignore any lines starting with `#`


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
