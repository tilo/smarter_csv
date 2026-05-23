# In-process parallel via the `parallel` gem

True CPU parallelism via forked child processes, coordinated by the `parallel` gem. Each worker is a separate Ruby process with its own GVL — when one is parsing, the others can parse too.

## When to use this

- **Rake tasks / CLI imports** where you want parallelism but don't have (or don't want to set up) a job queue.
- **Single-machine processing** where Sidekiq's persistence and retry guarantees are overkill.
- **Backfills and one-off migrations** — fast, ephemeral, fan-out-and-die.

This is the "I have N cores, use them" pattern. No Redis, no DB queue table, no orchestration — just fork, work, join.

## Required gem

```
gem install parallel
```

## POSIX only

`Parallel.map(in_processes: N)` uses `fork`, which doesn't exist on Windows. The example exits early if run on Windows. JRuby also lacks fork. On those platforms, fall back to `../sidekiq/` (with a real Sidekiq worker, not `Testing.inline!`).

## The code

```ruby
slices  = SmarterCSV.slice(path, slice_size: 50_000, chunk_size: 500)
results = Parallel.map(slices, in_processes: Parallel.processor_count) do |slice|
  SmarterCSV.process_slice(slice) do |batch|
    Model.insert_all(batch)
  end
  reader.headers # or anything else the parent needs to aggregate
end
```

`Parallel.map` preserves input order in `results`, so slice ordering is implicit. For pure side-effect workflows (insert and forget), use `Parallel.each` instead and persist via a shared store — see `../parallel_each_tempfiles/`.

## What the demo prints

The example slices a 12-row mixed-width CSV into 3 slices, then dispatches them to up to `Parallel.processor_count` forked workers. Each worker's output is tagged with its `pid` so you can see which fork did which slice. Final output: all rows in slice order, with global row indices.

## Rails caveat

`Parallel.each(in_processes:)` forks the parent, and forked children inherit the parent's ActiveRecord connection pool — including any open connections. The first child to use a connection corrupts it for the parent and all siblings. Always reconnect at the top of each worker:

```ruby
Parallel.each(slices, in_processes: 8, start: ->(_, _) {
  ActiveRecord::Base.connection_handler.clear_all_connections!
}) { |slice| ... }
```

Other fork-unsafe shared state (Redis connections, open log file handles) needs the same treatment. This is the #1 source of "works in dev, fails under load" bugs in fork-based importers.

## Caveats

- **Headers / warnings / errors aggregation** isn't shown here. Each worker has its own `reader.headers` etc.; the parent collects them via `Parallel.map`'s return value. See `docs/parallel_slicing.md` for the aggregation patterns.
- **Process startup cost.** Forking N workers takes a few hundred milliseconds; for tiny files this dominates. Slicing is worth it once parse time exceeds fork-setup time, typically multi-million-row files.

## See also

- `../serial_loop/` — the same pattern without parallelism. Compare the code shape.
- `../parallel_each_tempfiles/` — variant using `Parallel.each` with per-slice tempfiles. Better for true "side-effect and discard" workflows.
- `../manual_fork/` — what the `parallel` gem does under the hood (`Process.fork` + `Process.wait`).
