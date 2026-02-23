
### Contents

  * [Introduction](./_introduction.md)
  * [Parsing Strategy](./parsing_strategy.md)
  * [The Basic Read API](./basic_read_api.md)
  * [The Basic Write API](./basic_write_api.md)
  * [**Batch Processing**](././batch_processing.md)
  * [Configuration Options](./options.md)
  * [Row and Column Separators](./row_col_sep.md)
  * [Header Transformations](./header_transformations.md)
  * [Header Validations](./header_validations.md)
  * [Column Selection](./column_selection.md)
  * [Data Transformations](./data_transformations.md)
  * [Value Converters](./value_converters.md)
  * [Bad Row Quarantine](./bad_row_quarantine.md)
    
--------------     

# Batch Processing

Processing CSV data in batches (chunks), allows you to parallelize the workload of importing data.
This can come in handy when you don't want to slow-down the CSV import of large files.

Setting the option `chunk_size` sets the max batch size.

When using a block, an optional second parameter `chunk_index` is passed, representing the 0-based index of the current chunk. This is useful for progress tracking and debugging:

```ruby
    SmarterCSV.process(filename, {chunk_size: 100}) do |chunk, chunk_index|
      puts "Processing chunk #{chunk_index}"
      MyModel.insert_all(chunk)
    end
```

## Example 1: How SmarterCSV processes CSV-files as chunks, returning arrays of hashes:
Please note how the returned array contains two sub-arrays containing the chunks which were read, each chunk containing 2 hashes.
In case the number of rows is not cleanly divisible by `:chunk_size`, the last chunk contains fewer hashes.

```ruby
     > pets_by_owner = SmarterCSV.process('/tmp/pets.csv', {:chunk_size => 2, :key_mapping => {:first_name => :first, :last_name => :last}})
       => [ [ {:first=>"Dan", :last=>"McAllister", :dogs=>"2"}, {:first=>"Lucy", :last=>"Laweless", :cats=>"5"} ],
            [ {:first=>"Miles", :last=>"O'Brian", :fish=>"21"}, {:first=>"Nancy", :last=>"Homes", :dogs=>"2", :birds=>"1"} ]
          ]
```

## Example 2: How SmarterCSV processes CSV-files as chunks, and passes arrays of hashes to a given block:
Please note how the given block is passed the data for each chunk as the first parameter (array of hashes),
with an optional second parameter for the chunk index (0-based).
The `process` method returns the number of chunks when called with a block.

```ruby
     > total_chunks = SmarterCSV.process('/tmp/pets.csv', {:chunk_size => 2, :key_mapping => {:first_name => :first, :last_name => :last}}) do |chunk, chunk_index|
         puts "Processing chunk #{chunk_index}..."
         chunk.each do |h|   # you can post-process the data from each row to your heart's content, and also create virtual attributes:
           h[:full_name] = [h[:first],h[:last]].join(' ')  # create a virtual attribute
           h.delete(:first) ; h.delete(:last)              # remove two keys
         end
         puts chunk.inspect   # we could at this point pass the chunk to a Resque worker..
       end

       Processing chunk 0...
       [{:dogs=>"2", :full_name=>"Dan McAllister"}, {:cats=>"5", :full_name=>"Lucy Laweless"}]
       Processing chunk 1...
       [{:fish=>"21", :full_name=>"Miles O'Brian"}, {:dogs=>"2", :birds=>"1", :full_name=>"Nancy Homes"}]
        => 2
```

## Example 3: Populate a MongoDB Database in Chunks of 100 records with SmarterCSV:
```ruby
    # using chunks:
    filename = '/tmp/some.csv'
    options = {:chunk_size => 100, :key_mapping => {:unwanted_row => nil, :old_row_name => :new_name}}
    n = SmarterCSV.process(filename, options) do |chunk|
          # we're passing a block in, to process each resulting hash / row (block takes array of hashes)
          # when chunking is enabled, there are up to :chunk_size hashes in each chunk
          MyModel.insert_all( chunk )   # insert up to 100 records at a time
    end

     => returns number of chunks we processed
```

---

# Modern Batch API — `each_chunk`

`Reader#each_chunk` is the modern API for chunked batch processing. It yields `(Array<Hash>, chunk_index)` — the same shape as the `process` block — but returns an `Enumerator` when called without a block, enabling more flexible composition.

## Configuration

Set `chunk_size` in options when constructing the Reader. `each_chunk` reads this value automatically:

```ruby
reader = SmarterCSV::Reader.new('big.csv', chunk_size: 500)
reader.each_chunk do |chunk, index|
  puts "Processing chunk #{index} (#{chunk.size} rows)"
  MyModel.insert_all(chunk)
end
```

If `chunk_size` is not set, `each_chunk` defaults to `SmarterCSV::Reader::DEFAULT_CHUNK_SIZE` (100) and emits a warning to STDERR:

```
SmarterCSV: chunk_size not set, defaulting to 100. Set chunk_size explicitly to suppress this warning.
```

Set `chunk_size` explicitly to suppress the warning and choose the right batch size for your use case.

## Simplified form

```ruby
SmarterCSV.each_chunk('big.csv', chunk_size: 500) do |chunk, index|
  MyModel.insert_all(chunk)
end
```

## Returns an Enumerator when called without a block

```ruby
reader = SmarterCSV::Reader.new('big.csv', chunk_size: 500)
reader.each_chunk.with_index do |chunk, index|
  puts "Chunk #{index}: #{chunk.size} rows"
end
```

## Example: Sidekiq parallel import

```ruby
reader = SmarterCSV::Reader.new('users.csv', chunk_size: 100)
reader.each_chunk do |chunk, index|
  ImportWorker.perform_async(chunk)
end
```

## Example: Resque parallel import

```ruby
reader = SmarterCSV::Reader.new('orders.csv', chunk_size: 200)
reader.each_chunk do |chunk, index|
  Resque.enqueue(OrderImportJob, chunk)
end
```

## Example: MongoDB bulk insert

```ruby
reader = SmarterCSV::Reader.new('products.csv', chunk_size: 500)
reader.each_chunk do |chunk, _index|
  MyModel.insert_all(chunk)
end
```

## Example: Progress tracking

```ruby
reader = SmarterCSV::Reader.new('big.csv', chunk_size: 1_000)
total = File.foreach('big.csv').count - 1  # subtract header row

reader.each_chunk do |chunk, index|
  processed = [(index + 1) * 1_000, total].min
  puts "#{processed}/#{total} rows processed"
  MyModel.insert_all(chunk)
end
```

## Interaction with `on_bad_row`

`each_chunk` respects all `on_bad_row` options. Bad rows are excluded from chunks and counted or routed to your handler:

```ruby
reader = SmarterCSV::Reader.new('data.csv',
  chunk_size: 500,
  on_bad_row: :collect,
)
reader.each_chunk do |chunk, index|
  MyModel.insert_all(chunk)
end
puts "Bad rows: #{reader.errors[:bad_row_count]}"
reader.errors[:bad_rows].each { |rec| puts "Line #{rec[:csv_line_number]}: #{rec[:error_message]}" }
```

See [Bad Row Quarantine](./bad_row_quarantine.md) for full details.

----------------
PREVIOUS: [The Basic Write API](./basic_write_api.md)  | NEXT: [Configuration Options](./options.md)
