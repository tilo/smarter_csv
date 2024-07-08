
# Notes




## NOTES on the use of Chunking and Blocks:
 * chunking can be VERY USEFUL if used in combination with passing a block to File.read_csv FOR LARGE FILES
 * if you pass a block to File.read_csv, that block will be executed and given an Array of Hashes as the parameter.
 * if the chunk_size is not set, then the array will only contain one Hash.
 * if the chunk_size is > 0 , then the array may contain up to chunk_size Hashes.
 * this can be very useful when passing chunked data to a post-processing step, e.g. through Sidekiq

## NOTES about File Encodings:
 * if you have a CSV file which contains unicode characters, you can process it as follows:

```ruby
       File.open(filename, "r:bom|utf-8") do |f|
         data = SmarterCSV.process(f);
       end
```
* if the CSV file with unicode characters is in a remote location, similarly you need to give the encoding as an option to the `open` call:
```ruby
       require 'open-uri'
       file_location = 'http://your.remote.org/sample.csv'
       open(file_location, 'r:utf-8') do |f|   # don't forget to specify the UTF-8 encoding!!
         data = SmarterCSV.process(f)
       end
```
