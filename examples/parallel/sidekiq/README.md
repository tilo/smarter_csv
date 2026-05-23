# Sidekiq worker pattern

Cross-process parallelism via Sidekiq jobs — the standard production deployment for Rails imports. Each slice becomes a job; Sidekiq workers (each in their own process) pull from Redis and process slices independently.

## When to use this

- **Production Rails imports.** This is the canonical shape — durable, retryable, observable, monitored.
- **Long-running imports** that need to survive deploys and restarts.
- **Multi-machine deployments** — Sidekiq workers can run on different hosts, all pulling slices from the same Redis.
- **When you want backpressure** — Sidekiq's concurrency setting caps how many slices run at once, so you don't overwhelm your DB.

## Required gems

```
gem install sidekiq activesupport
```

For production, Sidekiq needs a real Redis. For local testing / demos, `Sidekiq::Testing.inline!` runs jobs synchronously in the calling process — no Redis required. The example uses inline mode so you can run it standalone.

## The worker code

```ruby
class ImportSliceJob
  include Sidekiq::Job

  def perform(slice_data)
    # 1. Recover the slice's symbol keys (Sidekiq's JSON roundtrip flattened them to strings)
    slice = slice_data.deep_symbolize_keys

    # 2. Restore symbol-valued arrays (headers) and symbol options (quote_escaping, etc.)
    slice[:headers] = slice[:headers].map(&:to_sym)
    slice[:options][:user_provided_headers] = slice[:options][:user_provided_headers].map(&:to_sym)
    %i[quote_escaping quote_boundary].each do |opt|
      slice[:options][opt] = slice[:options][opt].to_sym if slice[:options][opt].is_a?(String)
    end

    # 3. Process the slice — same API as in-process serial / parallel
    SmarterCSV.process_slice(slice) do |batch|
      Model.insert_all(batch)
    end
  end
end
```

The producer side stays simple:

```ruby
SmarterCSV.slice(path, slice_size: 50_000, chunk_size: 500).each do |slice|
  ImportSliceJob.perform_async(slice)
end
```

## Why the deep_symbolize_keys dance

Sidekiq serializes job args as JSON, even in `Testing.inline!` mode (to faithfully simulate production). JSON lossily flattens Ruby symbols to strings:

- Hash keys: `slice[:row_offset]` → arrives as `slice["row_offset"]` on the worker
- Array elements: `[:a, :b, :c, :d]` → arrives as `["a", "b", "c", "d"]`
- Symbol-valued options: `quote_escaping: :auto` → arrives as `quote_escaping: "auto"`

`Hash#deep_symbolize_keys` (from ActiveSupport) recursively re-symbolizes Hash keys. For arrays-of-symbols and the few symbol-valued options, you need explicit `.map(&:to_sym)` / `.to_sym` since `deep_symbolize_keys` only touches Hash keys, not array elements or values.

**Don't use Marshal+Base64** as a workaround. It's brittle across Ruby major versions, adds ~33% size overhead, and isn't idiomatic in 2026. The symbolize-keys + targeted-conversion pattern is the canonical answer.

## Sidekiq.strict_args!(false)

By default, Sidekiq 8 rejects non-JSON-native job args at enqueue time. Slice hashes contain symbol keys and arrays of symbols, so `ImportSliceJob.perform_async(slice)` would raise. Disabling strict_args allows the slice through — Sidekiq still JSON-roundtrips it on the wire, the worker recovers symbols. Same outcome with strict_args on or off; turning it off just avoids a pre-enqueue rejection.

## What the demo prints

The inline example slices a 12-row mixed-width CSV into 3 slices, enqueues 3 jobs, and (because of `Sidekiq::Testing.inline!`) runs them synchronously in the calling process. Output shows each "worker" (the same pid in inline mode) processing one slice, with the slice's row_offset, parsed rows, and the headers that slice discovered.

## Production deployment

For real Sidekiq workers on real Redis:

1. **Remove `Sidekiq::Testing.inline!`** — let perform_async push to Redis.
2. **Run `sidekiq` workers** — `bundle exec sidekiq -c 10` for 10 concurrent slice jobs per process.
3. **Choose a shared store** for per-worker outputs. See `../sidekiq_db_table/` (ActiveRecord) or `../sidekiq_redis_counter/` (Redis hash + atomic counter).
4. **Pair with an aggregator job** to combine per-worker outputs after all slices done. See `../sidekiq_aggregator/`.
5. **Make workers idempotent** for retry safety. See `../sidekiq_retry/`.

## See also

- `../sidekiq_aggregator/` — fan-in pattern: aggregator job runs after all slices done.
- `../sidekiq_retry/` — idempotent workers via `upsert_all` for retry safety.
- `../sidekiq_db_table/`, `../sidekiq_redis_counter/` — two ways to persist per-worker outputs.
- `../goodjob_solid_queue/` — same worker shape, different queue backend (no Redis).
- `docs/parallel_slicing.md` "Aggregating per-worker state across workers" — the full aggregation patterns documentation.
