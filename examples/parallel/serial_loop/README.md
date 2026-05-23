# Serial loop — in-process, no parallelism

The simplest pattern for slice-mode processing: produce slices, iterate over them in one Ruby process, process each one in turn. No worker pool, no orchestration, no infrastructure.

## When to use this

- **Rake tasks** that don't need to fan out — one-off imports, cleanup jobs, ad-hoc data migrations.
- **CLI imports** where a single process is fine.
- **Environments without Sidekiq / a job queue** — small services, sidecar tools, ETL on a single machine.
- **Testing the slice path** before adding the deployment complexity of parallel workers.

You're not getting parallelism — parsing happens sequentially, just slice-by-slice instead of one continuous stream. The advantages over `SmarterCSV.process(path)` for this case are:

- Memory bounded per slice (workers only hold one slice's rows at a time, not the whole file)
- Each slice is independently restartable on failure (`slice[:row_offset]` + retry tooling)
- Same code shape as the parallel variants — easy to upgrade later

## The code

```ruby
slices = SmarterCSV.slice(path, slice_size: 4)

slices.each do |slice|
  SmarterCSV.process_slice(slice).each_with_index do |row, i|
    global_row = slice[:row_offset] + i
    # do something with row — insert into DB, transform, etc.
  end
end
```

Global row numbers are recovered as `slice[:row_offset] + local_index`. This stays consistent across all slice-mode patterns (parallel, Sidekiq, etc.) — the producer's row count anchors every consumer.

## What the demo prints

Running `bundle exec ruby example.rb` against the inline 12-row CSV (header `a,b,c,d` + 12 data rows of mixed widths) produces three slices of 4 rows each. For each slice the output shows the slice's byte range and each parsed row with its global row index. Rows wider than the header carry synthetic `:column_5..8` keys; rows that are exactly 4 columns wide carry just `:a..:d`.

## Caveats

- **Not parallel.** If parsing is the bottleneck, this won't speed it up. See `../parallel_gem/` for in-process true parallelism, or `../sidekiq/` for cross-process parallelism.
- **Sequential failure recovery is your problem.** If slice 5 of 10 raises, slices 6–10 don't run. Restart-on-failure is naturally one-slice-at-a-time in this pattern; if you want resumable bulk imports, persist progress (e.g., `last_completed_row_offset` in a DB row) and skip ahead on restart.

## See also

- `../chunks_only/` — the pre-1.18.0 baseline using `chunk_size:` only. Compare the code shape against this one.
- `../parallel_gem/` — adds true parallelism via forked processes.
