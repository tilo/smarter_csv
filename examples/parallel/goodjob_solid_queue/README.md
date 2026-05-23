# GoodJob / Solid Queue — Postgres-backed queue alternatives

Same slice-mode worker pattern as Sidekiq, different queue backend. Both GoodJob and Solid Queue are ActiveJob-based and use **Postgres** (or your existing app DB) as the queue — no separate Redis required. Solid Queue is the Rails 8 default.

The point of this example: **the worker code is queue-backend-agnostic**. Switch from Sidekiq to GoodJob to Solid Queue without changing the `process_slice` call or anything that touches SmarterCSV. The only differences are the framework `include` (or superclass) and queue-specific options.

## When to use one or the other

| Queue          | Strengths                                                    | Watch out for                                         |
| -------------- | ------------------------------------------------------------ | ----------------------------------------------------- |
| **Sidekiq**    | Highest throughput; large ecosystem; mature                  | Requires Redis as separate dep                        |
| **GoodJob**    | Postgres-backed; rich UI; ActiveJob-first                    | Postgres-only; lower throughput ceiling than Sidekiq   |
| **Solid Queue** | Rails 8 default; multi-DB support (PG/MySQL/SQLite); minimal | Newer (1.x); ecosystem still maturing                 |
| **Resque**     | Older; simple; Redis-backed                                  | Less actively maintained; classic-style API           |

For SmarterCSV slice mode, **all four work identically**. Pick based on your operational preferences (Redis vs Postgres for queue; Sidekiq UI vs GoodJob UI; etc.).

## The worker code (identical across all queue backends)

```ruby
class ImportSliceJob < ApplicationJob   # GoodJob / Solid Queue / Resque-with-ActiveJob
  queue_as :imports
  retry_on StandardError, attempts: 5, wait: :polynomially_longer

  def perform(slice_data, batch_id)
    slice = slice_data.deep_symbolize_keys
    slice[:headers] = slice[:headers].map(&:to_sym)
    slice[:options][:user_provided_headers] = slice[:options][:user_provided_headers].map(&:to_sym)
    %i[quote_escaping quote_boundary].each do |opt|
      slice[:options][opt] = slice[:options][opt].to_sym if slice[:options][opt].is_a?(String)
    end

    reader = SmarterCSV::Reader.new(slice[:input], slice[:options])
    reader.process_slice(slice) { |batch| Model.upsert_all(batch, unique_by: :external_id) }

    SliceResult.create!(batch_id: batch_id, row_offset: slice[:row_offset], headers: reader.headers, warnings: reader.warnings, errors: reader.errors)
  end
end
```

The **only** difference from the Sidekiq version is the parent class (`< ApplicationJob` instead of `include Sidekiq::Job`). The JSON-roundtrip pattern, the SmarterCSV calls, the persistence — all identical.

## Producer

```ruby
class EnqueueImportJob < ApplicationJob
  def perform(path)
    batch_id = SecureRandom.uuid
    SmarterCSV.slice(path, slice_size: 50_000, chunk_size: 500).each do |slice|
      ImportSliceJob.perform_later(slice, batch_id)   # use perform_later for ActiveJob
    end
  end
end
```

`perform_later` is the ActiveJob equivalent of Sidekiq's `perform_async`.

## Why this example is a sketch only

GoodJob and Solid Queue need a full Rails app to run — ActiveRecord configured, the queue migrations applied, the queue process running, etc. Spinning that up in a standalone `.rb` script is more setup than it's worth for a demo.

The runnable Sidekiq version (`../sidekiq/example.rb`) shows the same worker pattern in working code; mentally substitute the include/class line and it's identical.

## Setup steps for a real GoodJob deployment

```
# 1. Add to Gemfile
gem 'good_job'

# 2. Install + migrate
bundle install
rails generate good_job:install
rails db:migrate

# 3. Configure the queue adapter
# config/application.rb
config.active_job.queue_adapter = :good_job

# 4. Start the worker process
bin/good_job start

# 5. Enqueue jobs from Rails console / a controller
ImportSliceJob.perform_later(slice, batch_id)
```

## Setup steps for Solid Queue (Rails 8 default)

```
# Solid Queue ships with Rails 8 — already configured if you started a new Rails 8 app.
# For older Rails apps:

gem 'solid_queue'

bin/rails solid_queue:install
bin/rails db:migrate

# config/application.rb
config.active_job.queue_adapter = :solid_queue

# Start the worker (Rails 8 has bin/jobs):
bin/jobs

# Enqueue:
ImportSliceJob.perform_later(slice, batch_id)
```

## Aggregation patterns

All the aggregation patterns from the Sidekiq examples work here too:

- **`../sidekiq_db_table/` equivalent** — `SliceResult` table works identically with GoodJob / Solid Queue.
- **`../sidekiq_redis_counter/` equivalent** — you'd add Redis as a side dep for the counter, OR use a Postgres row counter (`UPDATE batches SET remaining = remaining - 1 WHERE id = $1 RETURNING remaining`) for an all-Postgres solution.
- **`../sidekiq_aggregator/` equivalent** — fan-in aggregator job; same code as the Sidekiq version, different `< ApplicationJob`.

## See also

- `../sidekiq/` — runnable Sidekiq version; sketch this against and substitute the worker class.
- `../sidekiq_db_table/` — ActiveRecord persistence pattern; transfers directly.
- `../sidekiq_retry/` — idempotent workers; `retry_on` is ActiveJob's equivalent of `sidekiq_options retry: 5`.
- `docs/parallel_slicing.md` "Other queue backends" — the section this example illustrates.
