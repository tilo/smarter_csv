# Progress reporting — visibility into long-running imports

For multi-million-row imports that run for many minutes, users need feedback. Per-slice progress reports give it: each worker publishes "I'm at row N of M for batch X" to a shared metrics sink (Statsd, Prometheus, a DB row, structured logs). The orchestrator reads the sink for the UI / dashboard / SLA monitor.

`slice[:row_offset] + local_chunk_index` is the global row anchor — works the same in serial, parallel-gem, and Sidekiq deployments. Reports come in arbitrary order from workers but the row anchors line up to produce a coherent timeline.

## When to use this

- **Long-running imports.** "100M-row import, ETA 45 minutes" — users won't tolerate a black box.
- **User-facing import dashboards.** "Customer XYZ uploaded a file 12 minutes ago; we've processed 4.2M rows so far."
- **SLA-driven imports.** Alert when an import falls behind expected pace.
- **Debugging slow workers.** Which slice is the slow one? Progress reports show it.

## What to report

- **Rows processed per slice** — `slice[:row_offset] + local_count`
- **Slice completion** — worker finished its slice (or failed)
- **Batch totals** — sum of per-slice progress
- **Per-worker rates** — rows/second; flag stragglers
- **Memory / CPU per worker** — for capacity planning

## The pattern

```ruby
class ImportSliceJob
  include Sidekiq::Job

  def perform(slice_data, batch_id)
    slice = slice_data.deep_symbolize_keys
    # ... normalize ...
    rows_done = 0
    SmarterCSV.process_slice(slice) do |batch|
      Model.insert_all(batch)
      rows_done += batch.size

      StatsD.increment("csv_import.batches", tags: ["batch_id:#{batch_id}"])
      StatsD.gauge(
        "csv_import.rows_processed",
        slice[:row_offset] + rows_done,
        tags: ["batch_id:#{batch_id}", "slice:#{slice[:row_offset]}"]
      )
    end
  end
end
```

The `slice[:row_offset] + rows_done` value is GLOBAL — sum across slices in your dashboard query, get total rows processed for the batch.

## What the demo prints

40-row CSV, 4 slices of 10 rows each, `chunk_size: 5` (so each slice yields 2 batches). The demo's `ProgressSink` is a stdout printer; output shows per-batch progress reports interspersed across slices, with both local (within-slice) and global (across-the-import) progress percentages.

## Production sinks

| Sink                       | Use case                                                           |
| -------------------------- | ------------------------------------------------------------------ |
| **StatsD / DogStatsD**     | High-throughput counters / gauges; cheap to call from every batch |
| **Prometheus**             | Scrape-based metrics; good for Kubernetes / time-series dashboards |
| **DB row (Rails)**         | `ImportProgress.find_by(batch_id:).update_all(rows_processed: ...)` — durable, queryable, integrates with admin UIs |
| **Structured logs**        | If you have a log aggregator (Datadog Logs, Splunk, ELK) — searchable, no separate metrics infra needed |
| **Sidekiq job metadata**   | `set_callback`s, custom job middleware — built-in but limited       |

## Caveats

- **Don't report too often.** A worker yielding chunks every 500 rows reports 200 times for a 100k-row slice. For 8 workers, that's 1600 StatsD calls per import. Fine for most metric backends but profile if your sink is sensitive.
- **Reports can arrive out of order.** Worker 3 might finish before worker 1. Use `slice[:row_offset]` as the row anchor so out-of-order reports still produce a coherent global view (sum or max-by-batch in your aggregator).
- **Sidekiq retries** mean a slice might report progress twice. Either tag reports with attempt number, or use idempotent gauges (`StatsD.gauge` sets-to-value rather than increment-by-value).
- **Failed workers** stop reporting. Pair with a heartbeat (worker reports "I'm alive" every 10s) if you need to detect stuck workers.

## See also

- `../sidekiq/` — base worker pattern; add progress calls inside the chunk-yield block.
- `../sidekiq_aggregator/` — the aggregator can read final progress from the sink to write the audit record.
