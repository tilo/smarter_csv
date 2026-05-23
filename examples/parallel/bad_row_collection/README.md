# Bad row collection across slices

Real-world CSVs have bad rows: unclosed quotes, wrong column counts, encoding glitches, truncated lines. SmarterCSV's `on_bad_row: :collect` mode captures them per worker instead of raising — `reader.errors[:bad_rows]` accumulates the error records as the worker processes its slice.

The aggregator collects these per-worker error records into a unified audit. Pair this with a "import what you can, surface what you couldn't" workflow — most imports complete normally, but a small audit table shows which rows didn't make it.

## When to use this

- **Tolerant imports** — production data has imperfections; refusing the whole file because one row is bad is rarely the right answer.
- **User-facing reports** — "We imported 9,847 rows; 13 were rejected. Here's why:" with a downloadable error report.
- **Pipeline observability** — track bad-row rates over time; alert when a source's quality degrades.
- **Manual correction workflows** — bad rows go to a queue; humans fix and re-import only those.

## The `on_bad_row:` options

| Mode         | What it does                                                                                       |
| ------------ | -------------------------------------------------------------------------------------------------- |
| `:raise`     | (default) Stop on the first bad row. Use for strict imports where any malformation is unacceptable. |
| `:skip`      | Silently drop bad rows. Increments `reader.errors[:bad_row_count]` but doesn't collect details.    |
| `:collect`   | Drop the row AND collect details into `reader.errors[:bad_rows]`. The most useful mode in practice. |
| `<Proc>`     | Custom callable — `->(err_record) { Sentry.capture_message(...) }` — for custom error sinks.       |

`:collect` carries (per bad row): `csv_line_number`, `file_line_number`, `error_class`, `error_message`, and optionally `raw_logical_line` (with `collect_raw_lines: true`).

## The pattern

```ruby
slices = SmarterCSV.slice(path, slice_size: 50_000, on_bad_row: :collect)

per_slice_audit = slices.map do |slice|
  reader = SmarterCSV::Reader.new(slice[:input], slice[:options])
  rows   = reader.process_slice(slice) { |batch| Model.upsert_all(batch) }
  {
    row_offset:    slice[:row_offset],
    good_rows:     reader.csv_line_count,
    bad_row_count: reader.errors[:bad_row_count] || 0,
    bad_rows:      reader.errors[:bad_rows]      || [],
  }
end

all_bad_rows = per_slice_audit.flat_map { |s|
  s[:bad_rows].map { |err| err.merge(global_row: s[:row_offset] + err[:csv_line_number]) }
}

ImportAudit.create!(
  batch_id:      batch_id,
  total_rows:    per_slice_audit.sum { |s| s[:good_rows] },
  bad_row_count: per_slice_audit.sum { |s| s[:bad_row_count] },
  bad_rows:      all_bad_rows,
)
```

The `slice[:row_offset] + err[:csv_line_number]` recovery gives users global row positions in the error report ("row 42,581 was bad"), which is what they need to look up the source.

## What the demo prints

A 10-row CSV with deliberately-introduced bad rows (unclosed quotes). The slicer cuts it into smaller slices; each worker collects bad rows locally; the aggregator combines them anchored on `slice[:row_offset]` so error positions are global. Output shows per-slice good/bad counts and the unified audit.

## Caveats

- **Slicer-side errors vs. worker-side errors.** The slicer's quote-aware scan can also fail on malformed input (unclosed quote at EOF, etc.) — in which case `SmarterCSV.slice` raises. The `:collect` mode applies to the WORKER's row-parsing, not the slicer's pre-scan. Validate your file enough on the slicer side that the scan succeeds.
- **Bad row count vs. errors.** With `:collect`, `bad_row_count` is the total and `bad_rows` is the array of detail records. With `:skip`, only the count is tracked (no detail array).
- **Memory.** Collecting bad row details uses memory proportional to bad-row count. For files where most rows are bad, switch to a streaming error sink (`<Proc>` mode with `->(err) { db.insert(...) }`) instead of accumulating in memory.
- **Aggregator must handle empty `bad_rows`.** Workers with no bad rows return `bad_rows: []` (or `nil` if you persist via `:bad_row_count` only). Defensive `|| []` everywhere.

## See also

- `../sidekiq/` — base pattern; add `on_bad_row: :collect` to the slice's options.
- `../sidekiq_aggregator/` — the aggregator job collects bad rows from per-worker outputs.
- `../parallel_validation/` — pre-import sanity checks; reject the file rather than collect bad rows.
- `docs/bad_row_quarantine.md` — full reference for SmarterCSV's bad row handling.
