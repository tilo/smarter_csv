# SmarterCSV

`smarter_csv` is a Ruby Gem for smarter importing of CSV Files as Array(s) of Hashes, suitable for direct processing with Mongoid or ActiveRecord, 
and parallel processing with Resque or Sidekiq.

`smarter_csv` has lots of features:
 * able to process large CSV-files
 * able to chunk the input from the CSV file to avoid loading the whole CSV file into memory
 * return a Hash for each line of the CSV file, so we can quickly use the results for either creating MongoDB or ActiveRecord entries, or further processing with Resque
 * able to pass a block to the `process` method, so data from the CSV file can be directly processed (e.g. Resque.enqueue )
 * allows to have a bit more flexible input format, where comments are possible, and col_sep,row_sep can be set to any character sequence, including control characters.
 * able to re-map CSV "column names" to Hash-keys of your choice (normalization)
 * able to ignore "columns" in the input (delete columns)
 * able to eliminate nil or empty fields from the result hashes (default)

NOTE; This Gem is only for importing CSV files - writing of CSV files is not supported.

### Why?

Ruby's CSV library's API is pretty old, and it's processing of CSV-files returning Arrays of Arrays feels 'very close to the metal'. The output is not easy to use - especially not if you want to create database records from it. Another shortcoming is that Ruby's CSV library does not have good support for huge CSV-files, e.g. there is no support for 'chunking' and/or parallel processing of the CSV-content (e.g. with Resque or Sidekiq),

As the existing CSV libraries didn't fit my needs, I was writing my own CSV processing - specifically for use in connection with Rails ORMs like Mongoid, MongoMapper or ActiveRecord. In those ORMs you can easily pass a hash with attribute/value pairs to the create() method. The lower-level Mongo driver and Moped also accept larger arrays of such hashes to create a larger amount of records quickly with just one call.

### Examples

The two main choices you have in terms of how to call `SmarterCSV.process` are:
 * calling `process` with or without a block
 * passing a `:chunk_size` to the `process` method, and processing the CSV-file in chunks, rather than in one piece.

#### Example 1a: How SmarterCSV processes CSV-files as array of hashes:
Please note how each hash contains only the keys for columns with non-null values.

     $ cat pets.csv
     first name,last name,dogs,cats,birds,fish
     Dan,McAllister,2,,,
     Lucy,Laweless,,5,,
     Miles,O'Brian,,,,21
     Nancy,Homes,2,,1, 
     $ irb
     > require 'smarter_csv'
      => true 
     > animals_array = SmarterCSV.process('/tmp/pets.csv')
      => [ {:first_name=>"Dan", :last_name=>"McAllister", :dogs=>"2"},
           {:first_name=>"Lucy", :last_name=>"Laweless", :cats=>"5"}, 
           {:first_name=>"Miles", :last_name=>"O'Brian", :fish=>"21"}, 
           {:first_name=>"Nancy", :last_name=>"Homes", :dogs=>"2", :birds=>"1"} 
         ]


#### Example 1b: How SmarterCSV processes CSV-files as chunks, returning arrays of hashes:
Please note how the returned array contains two sub-arrays containing the chunks which were read, each chunk containing 2 hashes.
In case the number of rows is not cleanly divisible by `:chunk_size`, the last chunk contains fewer hashes.

     > animals_array = SmarterCSV.process('/tmp/pets.csv', {:chunk_size => 2, :key_mapping => {:first_name => :first, :last_name => :last}})
       => [ [ {:first=>"Dan", :last=>"McAllister", :dogs=>"2"}, {:first=>"Lucy", :last=>"Laweless", :cats=>"5"} ], 
            [ {:first=>"Miles", :last=>"O'Brian", :fish=>"21"}, {:first=>"Nancy", :last=>"Homes", :dogs=>"2", :birds=>"1"} ]
          ]

#### Example 2: Reading a CSV-File in one Chunk, returning one Array of Hashes:

    filename = '/tmp/input_file.txt' # TAB delimited file, each row ending with Control-M
    recordsA = SmarterCSV.process(filename, {:col_sep => "\t", :row_sep => "\cM"})  # no block given

    => returns an array of hashes

#### Example 3: Populate a MySQL or MongoDB Database with SmarterCSV:

    # without using chunks:
    filename = '/tmp/some.csv'
    n = SmarterCSV.process(filename, {:key_mapping => {:unwanted_row => nil, :old_row_name => :new_name}}) do |array|
          # we're passing a block in, to process each resulting hash / =row (the block takes array of hashes)
          # when chunking is not enabled, there is only one hash in each array
          MyModel.create( array.first )
    end

     => returns number of chunks / rows we processed 


#### Example 4: Populate a MongoDB Database in Chunks of 100 records with SmarterCSV:

    # using chunks:
    filename = '/tmp/some.csv'
    n = SmarterCSV.process(filename, {:chunk_size => 100, :key_mapping => {:unwanted_row => nil, :old_row_name => :new_name}}) do |chunk|
          # we're passing a block in, to process each resulting hash / row (block takes array of hashes)
          # when chunking is enabled, there are up to :chunk_size hashes in each chunk
          MyModel.collection.insert( chunk )   # insert up to 100 records at a time
    end

     => returns number of chunks we processed


#### Example 5: Reading a CSV-like File, and Processing it with Resque:

    filename = '/tmp/strange_db_dump'   # a file with CRTL-A as col_separator, and with CTRL-B\n as record_separator (hello iTunes)
    n = SmarterCSV.process(filename, {:col_sep => "\cA", :row_sep => "\cB\n", :comment_regexp => /^#/,
            :chunk_size => 100 , :key_mapping => {:export_date => nil, :name => :genre}}) do |chunk|
        Resque.enque( ResqueWorkerClass, chunk ) # pass chunks of CSV-data to Resque workers for parallel processing
    end
    => returns number of chunks


## See also:

  http://www.unixgods.org/~tilo/Ruby/process_csv_as_hashes.html



## Installation

Add this line to your application's Gemfile:

    gem 'smarter_csv'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install smarter_csv


## Changes

#### 1.0.0 (2012-07-29)

 * renamed `SmarterCSV.process_csv` to `SmarterCSV.process`.

#### 1.0.0.pre1 (2012-07-29)



## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Added some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request

