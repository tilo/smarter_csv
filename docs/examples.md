
### Contents

  * [Introduction](./_introduction.md)
  * [The Basic API](./basic_api.md)
  * [Batch Processing](././batch_processing.md)
  * [Configuration Options](./options.md)
  * [Row and Column Separators](./row_col_sep.md)
  * [Header Transformations](./header_transformations.md)
  * [Header Validations](./header_validations.md)
  * [Data Transformations](./data_transformations.md)
  * [Value Converters](./value_converters.md)
    
--------------    

# Examples

Here are some examples to demonstrate the versatility of SmarterCSV.

**It is generally recommended to rescue `SmarterCSV::Error` or it's sub-classes.**

By default SmarterCSV determines the `row_sep` and `col_sep` values automatically. In cases where the automatic detection fails, an exception will be raised, e.g. `NoColSepDetected`. Rescuing from these exceptions will make sure that you don't miss processing CSV files, in case users upload CSV files with unexpected formats.

In rare cases you may have to manually set these values, after going through the troubleshooting procedure described above.

## Example 1a: How SmarterCSV processes CSV-files as array of hashes:
Please note how each hash contains only the keys for columns with non-null values.

```ruby
     $ cat pets.csv
     first name,last name,dogs,cats,birds,fish
     Dan,McAllister,2,,,
     Lucy,Laweless,,5,,
     Miles,O'Brian,,,,21
     Nancy,Homes,2,,1,
     $ irb
     > require 'smarter_csv'
      => true
     > pets_by_owner = SmarterCSV.process('/tmp/pets.csv')
      => [ {:first_name=>"Dan", :last_name=>"McAllister", :dogs=>"2"},
           {:first_name=>"Lucy", :last_name=>"Laweless", :cats=>"5"},
           {:first_name=>"Miles", :last_name=>"O'Brian", :fish=>"21"},
           {:first_name=>"Nancy", :last_name=>"Homes", :dogs=>"2", :birds=>"1"}
         ]
```


## Example 3: Populate a MySQL or MongoDB Database with SmarterCSV:
```ruby
    # without using chunks:
    filename = '/tmp/some.csv'
    options = {:key_mapping => {:unwanted_row => nil, :old_row_name => :new_name}}
    n = SmarterCSV.process(filename, options) do |array|
          # we're passing a block in, to process each resulting hash / =row (the block takes array of hashes)
          # when chunking is not enabled, there is only one hash in each array
          MyModel.create( array.first )
    end

     => returns number of chunks / rows we processed
```

## Example 4: Processing a CSV File, and inserting batch jobs in Sidekiq:
```ruby
    filename = '/tmp/input.csv' # CSV file containing ids or data to process
    options = { :chunk_size => 100 }
    n = SmarterCSV.process(filename, options) do |chunk|
      Sidekiq::Client.push_bulk(
        'class' => SidekiqIndividualWorkerClass,
        'args' => chunk,
      )
      # OR:
      # SidekiqBatchWorkerClass.process_async(chunk ) # pass an array of hashes to Sidekiq workers for parallel processing
    end
    => returns number of chunks
```
