
### Contents

  * [Introduction](./_introduction.md)
  * [Migrating from Ruby CSV](./migrating_from_csv.md)
  * [Ruby CSV Pitfalls](./ruby_csv_pitfalls.md)
  * [Parsing Strategy](./parsing_strategy.md)
  * [The Basic Read API](./basic_read_api.md)
  * [The Basic Write API](./basic_write_api.md)
  * [Batch Processing](./batch_processing.md)
  * [**Slicing & Parallel Processing**](./parallel_slicing.md)
  * [Configuration Options](./options.md)
  * [Row and Column Separators](./row_col_sep.md)
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
  * [Release Notes](./releases/1.18.0/changes.md)

--------------

# Parallel slice-mode processing

Slice mode lets you parallelize CSV processing across workers — Sidekiq jobs, forked processes (e.g. via the `parallel` gem), or a simple in-process loop. SmarterCSV does the work of identifying logical-row boundaries quote-aware (so quoted fields with embedded newlines stay intact) and produces tiny pointers describing each chunk of work; your application chooses the fan-out mechanism.

This document covers the user-facing API and the patterns for aggregating per-worker state (headers, warnings, errors) into a unified result.

## When slice mode is worth using

After SmarterCSV 1.17.0, parsing a large CSV is **CPU-bound, not I/O-bound** — Ruby allocations (hash construction, symbol keys, numeric conversions) dominate. The GVL means thread-based parallelism gives essentially nothing for the expensive half. To use multiple cores you need **process-level parallelism**.

That said, profile your bottleneck first. For most Rails imports the real wall is the **database write** (`insert_all` of millions of rows, index maintenance, lock contention). Parallelizing the parse alone helps less than you might hope. The slice-mode pattern below parallelizes **both** parsing and writing (each worker does its own `insert_all`), so it helps either way — but set expectations.

For small files (under a few hundred thousand rows), the simpler `SmarterCSV.process(path)` is faster end-to-end than orchestrating workers.

## The API

Two module-level methods:

```ruby
SmarterCSV.slice(path, slice_size:, **opts) → Array<slice>
SmarterCSV.process_slice(slice, &block)     → parsed rows (or chunked batches)
```

`SmarterCSV.slice` does one cheap quote-aware pass over a seekable input. It parses and fully processes the header line once (transformations, `key_mapping`, `headers_in_file: false` + `user_provided_headers:` handling, BOM stripping, validations), runs auto-detection once, then scans the rest finding logical-row boundaries. It returns an Array of slice hashes, each describing up to `slice_size` logical rows.

`SmarterCSV.process_slice(slice, &block)` is the worker-side entry point. It reads the bytes for one slice from the original file, parses them with the slice's pre-baked options, and yields rows (or `chunk_size:`-sized batches) to your block — same row-by-row vs. chunked behavior as `SmarterCSV.process(path)`.

## Two row-count knobs

These options measure different things at different scales:

| Option        | Scale          | Meaning                                                                       |
| ------------- | -------------- | ----------------------------------------------------------------------------- |
| `slice_size:` | 10k–100k rows  | Rows per worker / per slice. The slicer's argument.                           |
| `chunk_size:` | 100–1000 rows  | Rows per yield to the block, within one worker. The Reader's existing option. |

They compose. `slice_size: 50_000, chunk_size: 500` means "split into 50k-row worker slices; within each worker, the block receives batches of 500 rows." A typical pattern for `Model.insert_all(batch)`.

## The slice hash

Each entry returned by `SmarterCSV.slice` looks like:

```ruby
{
  row_offset: 50_000,                       # 0-based global row index of this slice's first row
  input:      "/path/to/big.csv",
  headers:    [:id, :name, :email, ...],    # fully-processed headers (symbols by default)
  from_byte:  1_048_576,                    # byte offset where this slice's first data row starts
  to_byte:    2_097_140,                    # byte offset just past its last data row (exclusive)
  options:    { col_sep: ",", row_sep: "\n", quote_char: '"', ...,
                file_encoding: "utf-8",
                headers_in_file: false,
                user_provided_headers: [:id, :name, :email, ...] }
}
```

The slice hash is a few hundred bytes — small enough to put directly in Sidekiq job args, Marshal to a forked child, or pass through any other IPC mechanism. The original file stays put; workers seek into it.

Global row numbers are recovered as `slice[:row_offset] + local_index`.

## End-to-end example: Sidekiq

```ruby
# Rails controller — receives upload, kicks off processing
class ImportsController < ApplicationController
  def create
    path = params[:file].tempfile.path
    EnqueueImportJob.perform_async(path)
    head :accepted
  end
end

# Producer job — runs once for the whole file
class EnqueueImportJob
  include Sidekiq::Job

  def perform(path)
    SmarterCSV.slice(path, slice_size: 50_000, chunk_size: 500).each do |slice|
      ImportSliceJob.perform_async(slice)
    end
  end
end

# Worker job — runs once per slice, N in parallel
class ImportSliceJob
  include Sidekiq::Job

  def perform(slice)
    SmarterCSV.process_slice(slice) do |batch|
      User.insert_all(batch)
    end
  end
end
```

**Rails caveat:** Sidekiq workers run in separate processes that don't share the parent's ActiveRecord connection state. The `sidekiq` gem already handles AR reconnection per-job. If you're doing this without Sidekiq (e.g., a fork-based runner), each child must reconnect: `ActiveRecord::Base.connection_handler.clear_all_connections!` or `establish_connection` in the child. The `pool:` setting in `database.yml` must be ≥ worker count. Other fork-unsafe shared resources (Redis connections, open log handles) need the same treatment.

## End-to-end example: in-process parallel

For one-off rake tasks or CLI imports where Sidekiq is overkill:

```ruby
require 'parallel'

slices = SmarterCSV.slice("big.csv", slice_size: 50_000, chunk_size: 500)

Parallel.each(slices, in_processes: Parallel.processor_count, start: -> (_, _) {
  ActiveRecord::Base.connection_handler.clear_all_connections!
}) do |slice|
  SmarterCSV.process_slice(slice) do |batch|
    User.insert_all(batch)
  end
end
```

Use `Parallel.each` (not `.map`) — `.each` doesn't Marshal results back, which is what you want for "process and discard / write to DB" workflows. `in_processes:` gives true parallelism; `in_threads:` is GVL-bound and useless for CPU work.

## End-to-end example: in-process serial

For small files or environments without `parallel` / Sidekiq:

```ruby
SmarterCSV.slice("data.csv", slice_size: 10_000, chunk_size: 500).each do |slice|
  SmarterCSV.process_slice(slice) do |batch|
    Model.insert_all(batch)
  end
end
```

Same code shape, no parallelism. Useful when you just want the streaming + batching benefits of `chunk_size:` without orchestrating workers.

## Aggregating per-worker state across workers

When you call `SmarterCSV.process(path)` on a whole file, the resulting Reader exposes a unified view of everything that happened. In slice mode, each **worker** has its own Reader and its own view, scoped to only what its slice contained. To present the same unified view to your application — equivalent to what `SmarterCSV.process(path)` produces — you need to aggregate across workers.

### What each worker carries after `process_slice`

For a Reader that processed one slice, after the call returns:

| Reader state      | Holds                                                                                                |
| ----------------- | ---------------------------------------------------------------------------------------------------- |
| `reader.headers`  | Canonical headers + any synthetic `:column_N` columns this worker's slice discovered                 |
| `reader.warnings` | Warnings emitted during this slice's processing, deduped by `(type, code)` within this worker        |
| `reader.errors`   | `{ bad_row_count:, bad_rows: }` for bad rows in this slice (when `on_bad_row: :skip` or `:collect`)   |

Each worker's view is **correct for its slice but incomplete for the file**. The whole-file equivalent only exists if someone unions across workers.

### Aggregation, in-process

For an in-process loop or `Parallel.each(in_processes:)` where Readers are accessible at the end:

```ruby
readers = []
slices.each do |s|
  reader = SmarterCSV::Reader.new(s[:input], s[:options])
  reader.process_slice(s) { |batch| Model.insert_all(batch) }
  readers << reader
end

# Headers — union, then sort synthetics by trailing position number
canonical    = slices.first[:headers]                    # the declared headers, identical across all slices
all_observed = readers.flat_map(&:headers).uniq          # union of canonical + any synthetics discovered
synthetics   = (all_observed - canonical).sort_by { |k| k.to_s[/\d+\z/].to_i }
full_headers = canonical + synthetics

# Warnings — concat across workers, then dedup by (type, code) with summed counts
all_warnings = readers.flat_map(&:warnings)
                      .group_by { |w| [w[:type], w[:code]] }
                      .map { |_, ws| ws.first.merge(count: ws.sum { |w| w[:count] }) }

# Errors — sum bad_row_count, concat bad_rows
all_errors = {
  bad_row_count: readers.sum { |r| r.errors[:bad_row_count] || 0 },
  bad_rows:      readers.flat_map { |r| r.errors[:bad_rows] || [] },
}
```

That's the canonical aggregation. About ten lines of application code, no extra abstractions needed.

If you don't need warning dedup across workers (e.g., you're treating each slice's warnings as independent), `readers.flat_map(&:warnings)` gives you the flat list. For headers, `Array#|` (set union) also works and preserves order in one expression: `readers.map(&:headers).reduce(:|)`.

### Aggregation, cross-process (Sidekiq)

Sidekiq is fundamentally fire-and-forget — there's no built-in mechanism for "get the return value of job X." Workers die after the job, taking their state with them. To aggregate, you write each worker's outputs (`reader.headers`, `reader.warnings`, `reader.errors`) somewhere shared, then read them back from the orchestrator after an "all done" signal fires. Three realistic patterns:

#### Pattern 1 — DB table (most common in Rails)

The worker `INSERT`s a row carrying its `reader.headers / .warnings / .errors`, keyed by some `batch_id`. The aggregator queries by `batch_id` after all jobs finish.

```ruby
# Worker job — persists its outputs alongside the actual insert work
class ImportSliceJob
  include Sidekiq::Job

  def perform(slice)
    reader = SmarterCSV::Reader.new(slice[:input], slice[:options])
    reader.process_slice(slice) { |batch| Model.insert_all(batch) }

    SliceResult.create!(
      batch_id: slice[:batch_id],
      headers:  reader.headers,
      warnings: reader.warnings,
      errors:   reader.errors,
    )
  end
end
```

**Pros:** durable, queryable from anywhere, integrates with the rest of your Rails state, easy to debug after the fact.
**Cons:** another table to manage and clean up; one extra write per worker; if CSV processing is fast, the DB write is a meaningful fraction of total time per slice.

#### Pattern 2 — Redis directly (atomic counter, no Sidekiq Pro needed)

Sidekiq already runs on Redis. You can write per-worker outputs to a Redis hash keyed by `batch_id`, and use an atomic `DECR` counter so the last worker to finish triggers the aggregation job:

```ruby
# Worker job
class ImportSliceJob
  include Sidekiq::Job

  def perform(slice)
    reader = SmarterCSV::Reader.new(slice[:input], slice[:options])
    reader.process_slice(slice) { |batch| Model.insert_all(batch) }

    Sidekiq.redis do |conn|
      conn.hset("import:#{slice[:batch_id]}:results", slice[:row_offset], JSON.dump(
        headers:  reader.headers,
        warnings: reader.warnings,
        errors:   reader.errors,
      ))
      conn.expire("import:#{slice[:batch_id]}:results", 3600)   # cleanup TTL
      remaining = conn.decr("import:#{slice[:batch_id]}:remaining")
      AggregateResultsJob.perform_async(slice[:batch_id]) if remaining.zero?
    end
  end
end
```

The producer pre-sets `remaining` to the total slice count:

```ruby
class EnqueueImportJob
  include Sidekiq::Job

  def perform(path)
    batch_id = SecureRandom.uuid
    slices   = SmarterCSV.slice(path, slice_size: 50_000, chunk_size: 500)

    Sidekiq.redis do |conn|
      conn.set("import:#{batch_id}:remaining", slices.size)
    end

    slices.each do |slice|
      ImportSliceJob.perform_async(slice.merge(batch_id: batch_id))
    end
  end
end
```

The atomic `DECR` lets the last worker to finish trigger the aggregation job — no Sidekiq Pro features needed, just primitive Redis ops.

**Pros:** no extra DB schema; one Redis write per worker, faster than DB; cleanup via TTL.
**Cons:** less queryable post-hoc; if Redis is flushed you lose state; raw Redis is less Rails-idiomatic than a model.

#### Pattern 3 — Sidekiq Pro Batches (the "callback" path)

If you have Sidekiq Pro, `Sidekiq::Batch` gives you an `on_complete` callback that fires after every job in the batch finishes:

```ruby
class EnqueueImportJob
  include Sidekiq::Job

  def perform(path)
    batch = Sidekiq::Batch.new
    batch.on(:complete, ImportBatchCallback, 'batch_id' => batch.bid)

    batch.jobs do
      SmarterCSV.slice(path, slice_size: 50_000, chunk_size: 500).each do |slice|
        ImportSliceJob.perform_async(slice.merge(batch_id: batch.bid))
      end
    end
  end
end
```

**But Batches only handle the "all done" signal — they don't carry per-job return values.** Sidekiq doesn't store job results anywhere. So you still need Pattern 1 or Pattern 2 underneath: workers persist their outputs to a DB table or Redis hash, and the `on_complete` callback reads from there. Batches just replace the atomic counter mechanic from Pattern 2 with a cleaner API.

```ruby
class ImportBatchCallback
  def on_complete(status, options)
    batch_id = options['batch_id']
    # Read from wherever workers wrote — DB table or Redis hash
    results  = SliceResult.where(batch_id: batch_id)

    canonical    = options['canonical_headers']
    all_observed = results.flat_map(&:headers).uniq
    synthetics   = (all_observed - canonical).sort_by { |k| k.to_s[/\d+\z/].to_i }
    full_headers = canonical + synthetics

    # ... and similar for warnings, errors using the same patterns as in-process
  end
end
```

For OSS Sidekiq (without Pro), the atomic-counter pattern from Pattern 2 is the equivalent of Batches.

#### Which pattern to use

| Setup                                                            | Recommended                                              |
| ---------------------------------------------------------------- | -------------------------------------------------------- |
| Rails app with Sidekiq Pro                                       | Pattern 1 (DB table) + Pattern 3 (Batches for callback)  |
| Rails app with OSS Sidekiq                                       | Pattern 1 (DB table) + atomic counter (from Pattern 2)   |
| Non-Rails / lightweight                                          | Pattern 2 (Redis) end-to-end                             |
| Cross-machine workers, shared S3 file                            | Pattern 1 against a shared Postgres; OR write per-slice JSON files to S3 keyed by `batch_id`, aggregate by listing the prefix |

The common thread across all three: **SmarterCSV gives you `reader.headers`, `reader.warnings`, `reader.errors` at the worker level; the application persists them somewhere shared and reads back after the "all done" trigger fires.** The gem deliberately stays out of this — your job framework already has opinions about coordination, and SmarterCSV shouldn't fight them.

### Why SmarterCSV doesn't provide a built-in aggregation helper

You might wonder why there isn't a `SmarterCSV.combine_slice_results(readers)` convenience that hides the union and dedup work. We considered it. The reasons against:

- It would only help the in-process case. Sidekiq workers can't return Readers across processes — by the time you want to aggregate, the Readers don't exist.
- The cross-process case needs application-owned persistence anyway. A helper that works in-process but not cross-process is a footgun.
- The whole pattern is about ten lines of straightforward Hash and Array manipulation. Documenting it once (here) is clearer than hiding it behind an abstraction.

The primitives (`reader.headers`, `reader.warnings`, `reader.errors`) are the right API surface. If a convenience proves useful later, we can add it without changing the underlying design.

## Aggregator job — the concrete "fan-in" recipe

Patterns 2 and 3 above both finish with "trigger the aggregator." Here's what that aggregator actually looks like in code, picking up where Pattern 2's last-finishing worker left off (`AggregateResultsJob.perform_async(batch_id)`):

```ruby
class AggregateResultsJob
  include Sidekiq::Job

  def perform(batch_id)
    raw = Sidekiq.redis do |conn|
      keys = conn.hkeys("import:#{batch_id}:results")
      keys.zip(conn.hmget("import:#{batch_id}:results", *keys))
    end
    results = raw.map { |row_offset, payload|
      JSON.parse(payload, symbolize_names: true).merge(row_offset: row_offset.to_i)
    }.sort_by { |r| r[:row_offset] }

    canonical    = results.first[:headers]                 # all slices carry the same canonical
    all_observed = results.flat_map { |r| r[:headers] }.uniq
    synthetics   = (all_observed - canonical).sort_by { |k| k.to_s[/\d+\z/].to_i }
    full_headers = canonical + synthetics

    all_warnings = results.flat_map { |r| r[:warnings] }
                          .group_by { |w| [w[:type], w[:code]] }
                          .map { |_, ws| ws.first.merge(count: ws.sum { |w| w[:count] }) }

    all_errors = {
      bad_row_count: results.sum { |r| r[:errors][:bad_row_count] || 0 },
      bad_rows:      results.flat_map { |r| r[:errors][:bad_rows] || [] },
    }

    ImportAudit.create!(
      batch_id:  batch_id,
      headers:   full_headers,
      warnings:  all_warnings,
      errors:    all_errors,
      row_count: results.sum { |r| r[:rows]&.size || 0 },
    )

    Sidekiq.redis { |conn| conn.del("import:#{batch_id}:results", "import:#{batch_id}:remaining") }

    # Notify the user, fire webhooks, publish to a Slack channel — anything that should run
    # exactly once when the whole import is complete.
    ImportMailer.completion_notice(batch_id).deliver_later
  end
end
```

This is what the abstract "orchestrator" in the previous patterns actually looks like. The same code works inside a Sidekiq Pro Batch `on_complete` callback or as a standalone job triggered by an atomic counter — the body is identical, only the entry point differs.

## Idempotent workers and retry safety

Sidekiq retries failed jobs automatically (5 retries by default, with exponential backoff). For the slice-mode pattern to survive retries cleanly, the worker has to be idempotent — running the same slice twice must produce the same end state.

Two design choices make this work:

1. **Use `upsert_all` instead of `insert_all`** for the per-row DB writes. Re-running a slice no-ops on rows already inserted; new rows from the second attempt land normally.
2. **Slices are deterministic by construction.** `SmarterCSV.slice` produces the same byte ranges every time (deterministic scan), so a retry of slice *k* reprocesses exactly the same rows. Combined with `upsert_all`, no row is inserted twice and no row is lost.

```ruby
class ImportSliceJob
  include Sidekiq::Job
  sidekiq_options retry: 5, dead: false  # exponential backoff; never go to the morgue

  def perform(slice_data)
    slice = slice_data.deep_symbolize_keys
    slice[:headers] = slice[:headers].map(&:to_sym)
    slice[:options][:user_provided_headers] = slice[:options][:user_provided_headers].map(&:to_sym)

    SmarterCSV.process_slice(slice) do |batch|
      Model.upsert_all(batch, unique_by: :external_id)
    end
  end
end
```

A worker that dies at row 30,000 of a 50,000-row slice gets re-enqueued by Sidekiq → reprocesses all 50,000 rows → the first 30,000 hit existing records (upsert no-ops), the remaining 20,000 land as new. Net effect: same as if the failure hadn't happened. **No state to clean up between retries.**

This requires a stable, non-CSV-derived unique key on the table (`external_id`, `customer_id`, etc.). If your CSV doesn't carry one, generate one deterministically in the import — typically a hash of the row's identifying columns. Don't rely on `csv_line_number` for uniqueness; row numbers shift if the source file is re-uploaded.

## Other queue backends (GoodJob, Solid Queue, Resque)

The Sidekiq examples above translate cleanly to other Ruby queue backends. The worker code shape is identical; only the framework `include` (or superclass) and the queue-specific options change.

```ruby
# GoodJob (Postgres-backed):
class ImportSliceJob < ApplicationJob
  queue_as :imports
  retry_on StandardError, attempts: 5, wait: :polynomially_longer

  def perform(slice_data)
    # ... identical to Sidekiq version above
  end
end

# Solid Queue (Rails 8 default, Postgres/MySQL/SQLite-backed):
class ImportSliceJob < ApplicationJob
  queue_as :imports

  def perform(slice_data)
    # ... identical
  end
end
```

The aggregator-job pattern, the idempotency + retry pattern, and the per-slice state-persistence pattern are queue-backend-agnostic. Switch backends without rewriting the SmarterCSV-facing code.

For the "all done" trigger:
- **Sidekiq Pro:** `Sidekiq::Batch` (Pattern 3 above).
- **OSS Sidekiq, GoodJob, Solid Queue, Resque, etc.:** atomic counter in the queue's backing store (Redis for Sidekiq/Resque; a Postgres row for GoodJob/Solid Queue). Same shape as Pattern 2.

## When NOT to use slice mode

- **Small files.** The cheap pass-over-the-file plus orchestration overhead dominates for files under a few hundred thousand rows. Use `SmarterCSV.process(path)` directly.
- **Non-seekable inputs.** Slice mode requires a file path (or any seekable source). Pipes, `Zlib::GzipReader`, HTTP bodies without Range support — these can't be sliced. Either decompress to a tempfile first (and then slice), or stay with `SmarterCSV.process(io)`.
- **When ordering matters across slices.** Worker order is non-deterministic. If downstream processing requires global row order, either re-sort by `slice[:row_offset] + local_index`, or stay with whole-file mode.

## Caveats

- **The original file must remain accessible to workers.** Slices carry the file path; workers `seek` and read directly. For cross-process workers, the file path must be readable from each worker's process. If you're running across machines, you'll typically point slices at an S3 key (with `get_object(range:)`) or a shared filesystem.
- **Re-runnable on failure.** Slice hashes are deterministic — slice *k* is always `[from_k, to_k)`. A worker that dies mid-slice can be retried with the same slice hash; the work is bounded and idempotent if your `insert_all` is.
- **`missing_headers:` semantics are the same as in whole-file mode.** If a data row is wider than the declared header line and `missing_headers: :raise` (or `:strict`) is set, the worker raises. With `:auto` (the default), the worker generates `:column_N` keys for the extra positions — position-stable across workers (slice A's `:column_8` and slice B's `:column_8` both refer to the file's 8th column position).
- **Synthetic column discovery is per-worker.** A row with extra columns produces a hash with the corresponding `:column_N` keys; rows without those columns simply omit the keys. This Ruby-hash raggedness is intentional — missing keys mean missing data, not nil placeholders. The aggregation pattern above unions across workers to give you the complete `:column_N` set if you want to know which synthetics appeared anywhere.

## Summary

Two methods, both module-level on `SmarterCSV`:

- `SmarterCSV.slice(path, slice_size:, **opts)` produces tiny slice hashes — one cheap quote-aware pass over the file.
- `SmarterCSV.process_slice(slice, &block)` is the worker entry point — same row/batch behavior as `SmarterCSV.process(path)`.

Pick your fan-out mechanism (`fork`, `Parallel.each`, Sidekiq, Solid Queue, etc.) — the slice hashes feed all of them. Per-worker state (`reader.headers`, `reader.warnings`, `reader.errors`) aggregates across workers using the patterns above to give you a unified view equivalent to whole-file processing.

----------------

PREVIOUS: [Batch Processing](./batch_processing.md) | NEXT: [Configuration Options](./options.md) | UP: [README](../README.md)
