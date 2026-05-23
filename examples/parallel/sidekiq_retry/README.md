# Sidekiq retry safety — idempotent workers via upsert_all

Sidekiq retries failed jobs automatically (5 retries with exponential backoff by default). For the slice-mode pattern to survive retries cleanly, the worker has to be idempotent: running the same slice twice must produce the same end state.

Two design choices make this safe:

1. **`upsert_all` instead of `insert_all`** — re-running a slice no-ops on rows already in the DB; new rows from the second attempt land normally.
2. **Slices are deterministic by construction** — `SmarterCSV.slice` produces the same byte ranges every time. A retried slice reprocesses exactly the same rows. Combined with `upsert_all`, no row is inserted twice and no row is lost.

## When to use this

- **Any production deployment.** Sidekiq retries are inevitable — DB blips, deploys mid-job, network glitches, OOM kills. Without idempotency, retries cause double-inserts or partial state.
- **Any data source where a stable natural key exists** — `external_id`, `customer_id`, `(tenant_id, sku)`, etc. The upsert needs SOMETHING to uniquely identify rows across retries.

## Required gems

```
gem install sidekiq activesupport
```

For production: ActiveRecord (for `upsert_all`) + a real Sidekiq.

## The code

```ruby
class ImportSliceJob
  include Sidekiq::Job
  sidekiq_options retry: 5    # default; explicit for clarity

  def perform(slice_data)
    slice = slice_data.deep_symbolize_keys
    # ... (normalize headers, options) ...

    SmarterCSV.process_slice(slice) do |batch|
      Model.upsert_all(batch, unique_by: :external_id)
    end
  end
end
```

The key line is `unique_by: :external_id` (or whatever your stable key is). On retry, Postgres `INSERT ... ON CONFLICT DO NOTHING` (which is what `upsert_all` compiles to) sees the existing rows and skips them. No errors raised, no duplicates inserted.

## What the demo demonstrates

The example uses a Hash (`FAKE_DB`) instead of a real DB; `FAKE_DB[key] ||= row` simulates the upsert (first writer wins, subsequent writers no-op). It enqueues 2 slices of 4 rows each, with slice `row_offset=4` rigged to fail on its first attempt. The output shows:

- Insert counts per row — the rigged slice's rows show 2 attempts; everyone else shows 1
- The `FAKE_DB` has all 8 rows after recovery, no duplicates
- The retry tracking shows slice 4 ran twice; slice 0 ran once

This is exactly what happens in production: Sidekiq retries the failed slice, the worker reprocesses all its rows, but the upsert dedups against what was inserted on attempt 1.

## Production deployment notes

- **Pick the right `unique_by:`.** It should be:
  - **Stable across retries** — don't use auto-incremented IDs or `csv_line_number` (those shift if the source file is re-uploaded)
  - **Stable across re-imports of the same source** — if a user uploads `customers.csv` twice, the second upload should idempotently upsert against the first
  - **Indexed in the DB** — Postgres requires an index on the unique columns for `ON CONFLICT` to work efficiently
- **Choose between `:do_nothing` and `:update`.** `upsert_all` defaults to update (incoming rows overwrite). If you want "first write wins," use `Model.insert_all(batch, on_duplicate: :skip)` instead (or whatever your adapter calls it).
- **If your CSV doesn't carry a natural key,** generate one deterministically: `unique_key = Digest::SHA256.hexdigest(row.values_at(:name, :email).join('|'))`. Same row → same key on retry.
- **Sidekiq dead jobs.** After 5 retries, Sidekiq pushes the job to the dead queue. If retries genuinely can't succeed (corrupted slice, persistent DB issue), the data for that slice is lost from the import. Combine with the aggregator pattern (see `../sidekiq_aggregator/`) and decide whether to fire the aggregator on partial results or wait for manual recovery.

## Caveats

- **Idempotency requires a unique key.** Without it, the worker can't tell new rows from rows already inserted. If your CSV has no natural key, the slicing pattern still works, but retries become unsafe — a failed-and-retried slice will double-insert.
- **`upsert_all` can be slow on huge batches.** Each ON CONFLICT check has cost. Test with realistic batch sizes.
- **The demo's `FAKE_DB[key] ||= row` is "first write wins."** Real production with `upsert_all` defaults to "last write wins" (incoming overwrites existing). Match the demo to your actual semantics by choosing the right adapter option.

## See also

- `../sidekiq/` — the base worker pattern (without retry handling).
- `../sidekiq_aggregator/` — fan-in for collecting per-worker outputs after retries complete.
- `docs/parallel_slicing.md` "Idempotent workers and retry safety" — the doc this example implements.
