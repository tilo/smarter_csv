# Sidekiq + DB table for per-worker state

The most common pattern for Rails apps. Each slice worker writes its outputs (`reader.headers`, `reader.warnings`, `reader.errors`) as a row in a `SliceResult` ActiveRecord table, keyed by `batch_id`. After all workers finish, the orchestrator queries the table by `batch_id` and aggregates.

This is "Pattern 1" from `docs/parallel_slicing.md`. Compared to the Redis variant (`../sidekiq_redis_counter/`): heavier-weight, but durable, queryable, and integrates naturally with the rest of your Rails state.

## When to use this

- **Rails apps with a queryable DB.** You already have one; one more table is cheap.
- **Long-running imports** where survivability matters — DB-persisted state survives Redis flushes.
- **Audit / observability requirements.** "Show me what happened for batch_id=X" is just `SliceResult.where(batch_id: X)`.
- **When you'll inspect the data post-import.** Rails console, admin dashboards, debugging — all just AR queries.

## Required gems

```
gem install sidekiq activesupport
```

For production: ActiveRecord too.

## The schema

```ruby
class CreateSliceResults < ActiveRecord::Migration[7.0]
  def change
    create_table :slice_results do |t|
      t.string  :batch_id,   null: false, index: true
      t.integer :row_offset, null: false
      t.jsonb   :headers
      t.jsonb   :warnings
      t.jsonb   :errors
      t.integer :row_count  # cheaper to read than counting elements in rows-jsonb if you persist rows
      t.timestamps
    end
    add_index :slice_results, [:batch_id, :row_offset], unique: true
  end
end

class SliceResult < ActiveRecord::Base
  # add validations, serialization, scopes as needed
end
```

The `(batch_id, row_offset)` unique index doubles as idempotency: if a worker is retried after partially completing, the second `create!` errors (which the worker can rescue and treat as a no-op).

## The worker

```ruby
class ImportSliceJob
  include Sidekiq::Job

  def perform(slice_data, batch_id)
    slice = slice_data.deep_symbolize_keys
    # ... (normalize headers, options) ...

    reader = SmarterCSV::Reader.new(slice[:input], slice[:options])
    rows   = reader.process_slice(slice) { |batch| Model.upsert_all(batch, unique_by: :external_id) }

    SliceResult.create!(
      batch_id:   batch_id,
      row_offset: slice[:row_offset],
      headers:    reader.headers,
      warnings:   reader.warnings,
      errors:     reader.errors,
      row_count:  reader.csv_line_count,
    )
  end
end
```

Note: we don't persist `rows` to the table. The actual data went to `Model.upsert_all` inside `process_slice`. SliceResult records the per-worker metadata only.

## The orchestrator

```ruby
# After all jobs done (via Sidekiq Batch on_complete, atomic counter, or external trigger):
results = SliceResult.where(batch_id: batch_id).order(:row_offset)

canonical    = results.first.headers  # all workers carry the same canonical
all_observed = results.flat_map(&:headers).uniq
synthetics   = (all_observed - canonical).sort_by { |k| k.to_s[/\d+\z/].to_i }
full_headers = canonical + synthetics

all_warnings = results.flat_map(&:warnings)
                      .group_by { |w| [w["type"], w["code"]] }
                      .map { |_, ws| ws.first.merge("count" => ws.sum { |w| w["count"] }) }

all_errors = {
  bad_row_count: results.sum { |r| r.errors["bad_row_count"] || 0 },
  bad_rows:      results.flat_map { |r| r.errors["bad_rows"] || [] },
}

ImportAudit.create!(batch_id: batch_id, headers: full_headers, warnings: all_warnings, errors: all_errors)
SliceResult.where(batch_id: batch_id).delete_all  # or keep for audit history
```

## What the demo prints

The example uses an Array (`SLICE_RESULTS_TABLE`) and `Struct` stand-in instead of a real ActiveRecord table. The structure mirrors the production shape: workers `create!` records keyed by batch_id; orchestrator queries by batch_id and aggregates. Output shows the per-slice records, then the aggregated headers and total row count.

## Production deployment notes

- **Trigger the orchestrator** via the atomic-counter pattern (`../sidekiq_aggregator/` shows this), Sidekiq Pro Batches, or an external scheduler.
- **Clean up after success.** `SliceResult.where(batch_id: batch_id).delete_all` once the audit record is written. Or keep them for history if you want to support "re-process from cached results."
- **Index `batch_id`.** All orchestrator queries are by this column.
- **JSONB columns** (Postgres) make `headers`/`warnings`/`errors` queryable: `SliceResult.where("warnings @> ?", [{type: "deprecation"}].to_json)`.

## Caveats

- **DB write per worker.** One INSERT per slice. For 100-slice imports, that's 100 extra writes on top of the actual data inserts. Negligible at typical scale but worth knowing.
- **DB connection pool sizing.** Workers each grab a connection; ensure `pool:` in `database.yml` ≥ concurrent worker count.
- **Schema migration overhead.** This adds a table to your app. If you do many imports, consider partitioning by `batch_id` or aging out old records.

## See also

- `../sidekiq_redis_counter/` — Pattern 2, Redis-based, no DB schema needed.
- `../sidekiq_aggregator/` — pairs naturally with this; the fan-in aggregator reads from SliceResult.
- `../sidekiq_retry/` — idempotent slice workers; the `(batch_id, row_offset)` unique index doubles as the retry safety net.
- `docs/parallel_slicing.md` "Pattern 1 — DB table" — the doc this example implements.
