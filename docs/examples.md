
### Contents

  * [Introduction](./_introduction.md)
  * [Migrating from Ruby CSV](./migrating_from_csv.md)
  * [Parsing Strategy](./parsing_strategy.md)
  * [The Basic Read API](./basic_read_api.md)
  * [The Basic Write API](./basic_write_api.md)
  * [Batch Processing](././batch_processing.md)
  * [Configuration Options](./options.md)
  * [Row and Column Separators](./row_col_sep.md)
  * [Header Transformations](./header_transformations.md)
  * [Header Validations](./header_validations.md)
  * [Column Selection](./column_selection.md)
  * [Data Transformations](./data_transformations.md)
  * [Value Converters](./value_converters.md)
  * [Bad Row Quarantine](./bad_row_quarantine.md)
  * [Instrumentation Hooks](./instrumentation.md)
  * [**Examples**](./examples.md)
  * [SmarterCSV over the Years](./history.md)

--------------

# Examples

Here are some real-world examples demonstrating the versatility of SmarterCSV.

**Rescue from `SmarterCSV::Error` (recommended):** By default SmarterCSV auto-detects row and column separators. In rare cases detection fails and raises an exception (e.g. `NoColSepDetected`). Rescuing from `SmarterCSV::Error` or its sub-classes ensures your application handles unexpected CSV formats gracefully.

## Example 1: CSV → Array of Hashes

Note how each hash only contains keys for columns with non-nil, non-empty values — columns with blank entries are omitted automatically:

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
 => [ {:first_name=>"Dan",   :last_name=>"McAllister", :dogs=>2},
      {:first_name=>"Lucy",  :last_name=>"Laweless",   :cats=>5},
      {:first_name=>"Miles", :last_name=>"O'Brian",    :fish=>21},
      {:first_name=>"Nancy", :last_name=>"Homes",      :dogs=>2, :birds=>1}
    ]
```

## Example 2: Importing into a Database

```ruby
filename = '/tmp/some.csv'
options = { key_mapping: { unwanted_row: nil, old_row_name: :new_name } }

n = SmarterCSV.process(filename, options) do |array|
  # called once per row (or once per chunk when chunk_size is set)
  MyModel.create(array.first)
end
# => returns number of chunks / rows processed
```

## Example 3: Batch Processing with Sidekiq

Processing in chunks reduces memory usage and enables parallel processing. The block receives the chunk index (0-based) as an optional second parameter:

```ruby
filename = '/tmp/input.csv'
options = { chunk_size: 100 }

n = SmarterCSV.process(filename, options) do |chunk, chunk_index|
  puts "Queueing chunk #{chunk_index} with #{chunk.size} records..."
  Sidekiq::Client.push_bulk(
    'class' => SidekiqWorkerClass,
    'args'  => chunk,
  )
end
# => returns number of chunks
```

## Example 4: Resumable CSV Import with Rails ActiveJob (Rails 8.1+)

Rails 8.1 introduced `ActiveJob::Continuable`, which lets a job pause and resume from exactly where it stopped — for example, when a deployment occurs mid-import or when a job queue needs draining.

The pattern: use `chunk_size` for batching and `chunk_index` as the resume cursor. On restart, skip chunks already committed:

```ruby
# app/jobs/import_csv_job.rb
class ImportCsvJob < ApplicationJob
  include ActiveJob::Continuable

  def perform(file_path)
    step :import_rows do |step|
      SmarterCSV.process(file_path, chunk_size: 500) do |chunk, chunk_index|
        next if chunk_index < step.cursor.to_i  # skip already-processed chunks on resume

        MyModel.import!(chunk)        # bulk-insert the chunk
        step.set! chunk_index + 1     # advance the cursor
      end
    end
  end
end
```

How it works:
- `step.cursor` starts as `nil` (→ `0` after `.to_i`), so the first run processes all chunks.
- If the job is interrupted after chunk 7, Rails persists the cursor as `8`.
- On the next run the file is re-read from the beginning; chunks 0–7 are skipped quickly via `next`, then processing resumes from chunk 8.
- `chunk_size: 500` is tunable — larger chunks mean fewer cursor saves; smaller chunks reduce re-work on retry.

> Requires Rails 8.1+ and a queue adapter that supports graceful shutdown
> (Sidekiq, Solid Queue). Other adapters will still process the CSV correctly
> but won't pause/resume mid-import.

--------------------
PREVIOUS: [Instrumentation Hooks](./instrumentation.md) | NEXT: [SmarterCSV over the Years](./history.md) | UP: [README](../README.md)
