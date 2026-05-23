# `Parallel.each` + per-slice tempfiles

The "side-effect workflow" variant of `Parallel.map`. Workers do their work (insert into DB, write to disk, call external services) and **don't return data to the parent** — `Parallel.each` doesn't Marshal results back. Output is whatever side effects each worker produced.

This is closer to what a real Rails importer does in production: each worker calls `Model.insert_all(batch)` and moves on; nothing comes back through the IPC layer. Saves Marshal cost; matches the natural shape of "process and discard."

This example uses per-slice tempfiles as a stand-in for DB writes so it runs standalone, but the pattern is the same as a real production importer.

## When to use this over `Parallel.map`

- **DB inserts.** You don't need the rows back; they went to the DB. Skip the Marshal overhead.
- **Per-slice file output.** Workers write to disk, parent doesn't need to see the contents.
- **External services.** Workers call APIs / push to queues; parent doesn't aggregate responses.

Use `Parallel.map` when you DO need the workers' results back — when the parent aggregates or reduces over them.

## Required gem

```
gem install parallel
```

## The pattern

```ruby
Dir.mktmpdir do |dir|
  Parallel.each(slices, in_processes: 8) do |slice|
    out_path = File.join(dir, format("slice_%010d.jsonl", slice[:row_offset]))
    File.open(out_path, 'w') do |f|
      SmarterCSV.process_slice(slice) do |batch|
        batch.each { |row| f.puts JSON.generate(row) }
      end
    end
  end

  # Parent reads side effects after workers complete
  Dir.glob(File.join(dir, 'slice_*.jsonl')).sort.each do |path|
    File.foreach(path) { |line| ... }
  end
end
```

Or for a real Rails importer:

```ruby
Parallel.each(slices, in_processes: 8, start: ->(_, _) {
  ActiveRecord::Base.connection_handler.clear_all_connections!
}) do |slice|
  SmarterCSV.process_slice(slice) do |batch|
    Model.upsert_all(batch, unique_by: :external_id)
  end
end
```

No tempfiles at all — workers write directly to the DB. The parent's job is just `Parallel.each` waiting for all workers to finish.

## What the demo prints

12-row CSV, 3 slices, workers parallel-write JSONL tempfiles. Parent reads them in row_offset order (via filename sort) and prints each line with the recovered global row index. The output structure is identical to the in-process serial loop's, but the work was done in parallel.

## Why the `%010d` filename trick

`Dir.glob(...).sort` sorts alphabetically. To recover slice order, encode `row_offset` in the filename as a fixed-width zero-padded integer: `slice_0000000000.jsonl`, `slice_0000000004.jsonl`, etc. Then alphabetical sort matches numeric sort.

Without zero-padding, `slice_10.jsonl` sorts before `slice_2.jsonl`. Padding to 10 digits handles row_offsets up to 10 billion — comfortably more than any realistic CSV.

## Caveats

- **No return values.** Workers can't pass data back to the parent through `Parallel.each`'s return. If you need per-worker outputs (errors, warnings, headers), persist them to disk / DB / Redis from inside the worker — same as the Sidekiq DB-table / Redis patterns.
- **Tempfile lifecycle.** `Dir.mktmpdir do |dir|` auto-cleans the tempdir on block exit. Workers must finish writing before the block exits, which `Parallel.each` guarantees (it joins all workers).
- **Tempfile concurrency.** Each worker writes its OWN file (named by row_offset). No file contention. If multiple workers tried to write to the same file, you'd need a mutex (and you'd lose the parallelism point).
- **Rails caveat:** forked children inherit the parent's DB connection. Always reconnect in the worker (`ActiveRecord::Base.connection_handler.clear_all_connections!`) — the `start:` callback is the canonical place.

## Comparison with `../parallel_gem/`

| Concern               | `parallel_gem/` (Parallel.map)                  | This (`parallel_each_tempfiles/`)                                |
| --------------------- | ----------------------------------------------- | ---------------------------------------------------------------- |
| Worker return value   | Marshaled back to parent                        | None (side effects only)                                         |
| Best for              | Aggregation, parent reduces over results        | Per-slice side effects (DB inserts, external services)           |
| IPC cost              | One Marshal per worker (proportional to result) | Zero (parent doesn't see results)                                |
| Production-realistic? | Less so — real importers don't Marshal rows back | Yes — real importers write to DB and move on                     |

## See also

- `../parallel_gem/` — `Parallel.map` version with rows Marshaled to parent. Compare and pick based on whether you need results back.
- `../parallel_filtering/` — uses this same per-slice tempfile pattern for CSV-to-CSV transforms.
- `../sidekiq/` — for cross-process / cross-machine parallelism instead of in-process forks.
