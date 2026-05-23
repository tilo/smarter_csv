# Sidekiq + Redis hash + atomic counter

Pattern 2 from `docs/parallel_slicing.md`. Each slice worker writes its outputs (`reader.headers`, `reader.warnings`, `reader.errors`) into a Redis hash keyed by `batch_id`. An atomic `DECR` counter tracks how many slices are still in flight; the **last worker** to finish atomically reads zero and triggers the aggregator job.

This is the OSS-Sidekiq-friendly alternative to `Sidekiq::Batch` (Pro feature). Same effect, no Pro license.

## When to use this

- **OSS Sidekiq** (no Pro license) — gets you Sidekiq::Batch-equivalent "all done" coordination via primitive Redis ops.
- **Lightweight deployments** — no ActiveRecord, no schema migrations, just Redis.
- **Short-lived results** — Redis TTLs auto-clean the per-worker outputs after a configurable window. Good when you don't need long-term audit history.
- **High-throughput imports** — Redis writes are an order of magnitude faster than DB writes; if the per-worker persistence is hot-path, Redis wins.

## Required gems

```
gem install sidekiq activesupport
```

For production: real Redis (which you already have if you're using Sidekiq).

## The pattern

```ruby
# Producer — pre-set the counter
batch_id = SecureRandom.uuid
slices   = SmarterCSV.slice(path, slice_size: 50_000, chunk_size: 500)
Sidekiq.redis { |c| c.set("import:#{batch_id}:remaining", slices.size) }
slices.each { |s| ImportSliceJob.perform_async(s, batch_id) }

# Worker — HSET output, DECR counter, last-to-zero triggers aggregator
class ImportSliceJob
  include Sidekiq::Job
  def perform(slice_data, batch_id)
    # ... normalize keys ...
    reader = SmarterCSV::Reader.new(slice[:input], slice[:options])
    rows   = reader.process_slice(slice)

    Sidekiq.redis do |c|
      c.hset("import:#{batch_id}:results", slice[:row_offset], JSON.dump(
        rows: rows, headers: reader.headers, warnings: reader.warnings, errors: reader.errors
      ))
      c.expire("import:#{batch_id}:results", 3600)
      remaining = c.decr("import:#{batch_id}:remaining")
      AggregateResultsJob.perform_async(batch_id) if remaining.zero?
    end
  end
end

# Aggregator — read all slice outputs from Redis, aggregate, clean up
class AggregateResultsJob
  include Sidekiq::Job
  def perform(batch_id)
    results = Sidekiq.redis do |c|
      c.hgetall("import:#{batch_id}:results").values.map { |s| JSON.parse(s, symbolize_names: true) }
    end.sort_by { |r| r[:row_offset] }

    # ... build full headers, dedup warnings, sum bad_row_count ...

    Sidekiq.redis { |c| c.del("import:#{batch_id}:results", "import:#{batch_id}:remaining") }
  end
end
```

## Why DECR is atomic

Redis commands are single-threaded per Redis instance. `DECR` atomically decrements the counter and returns the new value. Even with 100 workers hitting it concurrently, exactly one of them gets the return value `0` — that's the "last" worker, and it's the only one that enqueues the aggregator. No double-firing, no missed signals.

This is the same property `Sidekiq::Batch` provides via its bookkeeping. The DIY version doesn't have the batch UI / nested batches / death callbacks, but for "fire exactly once after N jobs complete," DECR is sufficient.

## What the demo prints

The example uses Ruby Hashes (`REDIS_HSET`, `REDIS_DECR`) instead of real Redis. Because `Sidekiq::Testing.inline!` runs jobs synchronously on a single thread, the atomicity guarantees hold by construction. Output: the producer pre-sets the counter, the workers run synchronously, each HSETs and DECRs, the last one fires the aggregator, the aggregator prints the unified result.

## Production deployment notes

- **Pre-set the counter in the producer.** `c.set("...:remaining", slices.size)`. The workers decrement from this initial value; without it, the counter starts at -1 and never hits zero correctly.
- **Set TTLs on all Redis keys.** The results hash and the counter both. `c.expire(key, 3600)` after writes ensures abandoned imports clean up after an hour. Without TTLs you accumulate dead state.
- **Handle worker death.** If a worker is killed before DECR runs (OOM, deploy mid-job), the counter never decrements for that slice. Sidekiq retries the job; the retry decrements as expected. As long as `unique_by:` upserts (see `../sidekiq_retry/`) prevent double-inserts, retries are safe.
- **Pair with idempotent workers** (`../sidekiq_retry/`). If a worker dies AFTER hset but BEFORE decr, the retry will hset again (overwriting the same field — idempotent) and then decr. Safe.
- **Watch Redis memory.** Each slice's output is one HSET field. For huge result sets you may want to persist `rows` to DB instead of Redis and keep only metadata (headers, errors) in Redis.

## Comparison vs Pattern 1 (DB table)

| Concern                | DB table                              | Redis hash                                              |
| ---------------------- | ------------------------------------- | ------------------------------------------------------- |
| Durability             | Persistent                            | TTL-bound; flush-able                                   |
| Queryability post-run  | SQL anywhere                          | Redis only (or replicate to DB)                         |
| Schema overhead        | One AR table + migration              | Zero schema                                             |
| Write speed            | DB insert per slice                   | Redis HSET per slice (~10–100× faster)                  |
| Coordination signal    | External (Batch / counter)            | Built-in via DECR                                       |
| Sidekiq license needed | OSS                                   | OSS                                                     |

Use DB table when you want post-import audit history and the writes are not hot. Use Redis when you want max throughput and short-lived state.

## See also

- `../sidekiq_db_table/` — Pattern 1, ActiveRecord-based alternative.
- `../sidekiq_aggregator/` — the full aggregator-job recipe, including how the orchestrator reads from Redis.
- `../sidekiq_retry/` — idempotent slice workers for retry safety.
- `docs/parallel_slicing.md` "Pattern 2 — Redis directly" — the doc this example implements.
