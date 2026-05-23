# Sidekiq fan-in — the aggregator job

Slice jobs persist their per-worker outputs to a shared store. An atomic counter tracks how many slices are still in flight; the **last worker** to finish triggers a separate aggregator job that reads from the shared store, builds the unified result (full headers, warnings, errors), and writes the import-complete record.

This is what "the orchestrator" actually looks like in code. The basic `../sidekiq/` example shows workers persisting; this one shows the fan-in.

## When to use this

- **Anywhere you want a single "import complete" signal.** Send the user an email, fire a webhook, publish a "ready" event — exactly once, after every slice is done.
- **When you need the unified result.** `reader.headers` from one slice covers only that slice's discoveries; the unified set requires the union across all slices.
- **When the import is part of a larger workflow.** The aggregator is the bridge to whatever runs next (rebuild a search index, enqueue downstream processing, etc.).

## Required gems

```
gem install sidekiq activesupport
```

For production: a real Redis (the shared store is a Redis hash; the counter is `Sidekiq.redis { |c| c.decr(...) }`).

## The code (two job classes)

```ruby
class ImportSliceJob
  include Sidekiq::Job
  def perform(slice_data, batch_id)
    # ... normalize keys (deep_symbolize_keys + targeted to_sym) ...
    reader = SmarterCSV::Reader.new(slice[:input], slice[:options])
    rows   = reader.process_slice(slice)

    # Persist per-worker output to the shared store
    Sidekiq.redis do |c|
      c.hset("import:#{batch_id}:results", slice[:row_offset], JSON.dump(
        rows:     rows,
        headers:  reader.headers,
        warnings: reader.warnings,
        errors:   reader.errors,
      ))
      c.expire("import:#{batch_id}:results", 3600)
    end

    # Atomic counter — the last worker triggers the aggregator
    remaining = Sidekiq.redis { |c| c.decr("import:#{batch_id}:remaining") }
    AggregateResultsJob.perform_async(batch_id) if remaining.zero?
  end
end

class AggregateResultsJob
  include Sidekiq::Job
  def perform(batch_id)
    results = Sidekiq.redis { |c|
      c.hgetall("import:#{batch_id}:results").values.map { |s| JSON.parse(s, symbolize_names: true) }
    }.sort_by { |r| r[:row_offset] }

    canonical    = results.first[:headers]
    full_headers = canonical | results.flat_map { |r| r[:headers] }

    # ... (warnings dedup, errors concat — see docs/parallel_slicing.md)

    ImportAudit.create!(batch_id: batch_id, headers: full_headers, ...)
    ImportMailer.completion_notice(batch_id).deliver_later
  end
end
```

The producer (omitted above for brevity) does:

```ruby
batch_id = SecureRandom.uuid
slices   = SmarterCSV.slice(path, slice_size: 50_000, chunk_size: 500)
Sidekiq.redis { |c| c.set("import:#{batch_id}:remaining", slices.size) }
slices.each { |s| ImportSliceJob.perform_async(s, batch_id) }
```

## The atomic-counter trick

The aggregator must fire **exactly once**, after every slice job has finished. Two approaches:

1. **Sidekiq Pro Batches** with `on_complete` callback (Pro license required).
2. **Atomic counter via Redis `DECR`** — works with OSS Sidekiq. Each worker decrements; the one that reads zero is the "last," and it enqueues the aggregator. `DECR` is atomic in Redis, so even with concurrent workers, exactly one of them sees the counter hit zero.

The example uses approach (2) because it works without Pro.

## What the demo prints

The standalone example uses in-memory Hashes (`SHARED_STORE`, `SHARED_COUNTER`, `AGGREGATED_RESULTS`) instead of Redis so it runs without infrastructure. The atomic-counter pattern is preserved (Ruby's integer decrement on a single thread is implicitly atomic in this context). Output: enqueue count, then the final aggregated result — total rows, unified headers including synthetics, warning/error counts.

## Production deployment notes

- **Replace `SHARED_STORE` with Redis hashes** — `Sidekiq.redis { |c| c.hset(key, field, JSON.dump(payload)) }`.
- **Replace `SHARED_COUNTER` with Redis `DECR`** — `Sidekiq.redis { |c| c.decr(key) }`. This is what makes the "exactly once" property hold under real concurrency.
- **Set TTLs** on the Redis keys so cleanup happens automatically: `c.expire("import:#{batch_id}:results", 3600)`.
- **Pre-set the counter** in the producer job: `c.set("import:#{batch_id}:remaining", slices.size)`. The producer creates the counter; the workers decrement it; the aggregator deletes the keys when done.
- **Handle failed workers.** If `ImportSliceJob` raises, Sidekiq retries (default 5 times). The counter isn't decremented until the job succeeds. If retries exhaust, the counter never hits zero and the aggregator never fires. Pair with `../sidekiq_retry/` (idempotent workers) for the safety net.

## Caveats

- **The aggregator job sees the union of per-worker views.** If worker N never ran (failed all retries, dead letter queue), its data isn't in the shared store and the aggregation is incomplete. Decide upfront: do you want the aggregator to fire on partial results or fail loud? The pattern above fires on partial; for "fail loud" you'd need a separate mechanism (e.g., track expected slice count separately and check it in the aggregator).
- **Workers race on `hset`.** Two workers writing to the same `hset` is safe (different fields), but be careful if you ever consolidate into a single Redis value type that doesn't support concurrent updates.

## See also

- `../sidekiq/` — the base worker pattern.
- `../sidekiq_redis_counter/` — focuses on the Redis-counter signaling alone, without the aggregator.
- `../sidekiq_retry/` — idempotent workers for retry safety; pairs naturally with this pattern.
- `docs/parallel_slicing.md` "Aggregator job — the concrete fan-in recipe" — the doc this example implements.
