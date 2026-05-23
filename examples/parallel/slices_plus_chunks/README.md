# Slices + chunks — the production sweet spot

The combined pattern. Two orthogonal knobs operating at different scales:

- **`slice_size:`** — work distribution. How many logical rows go into one slice / worker. Typical: 10k–100k.
- **`chunk_size:`** — batch granularity within a worker. How many rows the block yields at once. Typical: 100–1000.

A typical Rails import: `SmarterCSV.slice("big.csv", slice_size: 50_000, chunk_size: 500)` produces tiny slice descriptors that fan out to workers; each worker parses its 50,000 rows and the block sees them in batches of 500, each batch fed to `Model.insert_all`.

## Why combine them

| Knob          | Without it                                                         | With it                                                              |
| ------------- | ------------------------------------------------------------------ | -------------------------------------------------------------------- |
| Just `slice_size:`   | Workers parse N rows each — but the block sees them row-by-row, one `insert` per row, slow DB writes | Workers parse N rows AND batch the writes — fast                     |
| Just `chunk_size:`   | One process parses the whole file sequentially, yielding batches — parse is single-CPU bottleneck | (impossible to combine with slicing unless you slice first)         |
| Both         |                                                                    | Parse parallelized across N workers, each doing fast batched writes  |

Slicing without chunks is "we parallelized the parse but ignored DB-write batching." Chunks without slicing is "we batched DB writes but didn't parallelize parsing." Together: both.

## The code

```ruby
slices = SmarterCSV.slice(path, slice_size: 50_000, chunk_size: 500)

# Producer (Rails controller, batch job, etc.):
slices.each { |slice| ImportSliceJob.perform_async(slice) }

# Worker (Sidekiq job or Parallel.each block):
SmarterCSV.process_slice(slice) do |batch|     # block sees batches of chunk_size rows
  Model.insert_all(batch, returning: false)
end
```

`chunk_size:` carries through the slice automatically (it's part of `slice[:options]`), so workers just call `process_slice` and the block is invoked with already-batched rows.

## What the demo prints

The example uses `slice_size: 6` and `chunk_size: 2` on a 12-row CSV, producing 2 slices of 6 rows each. Within each slice, the block is invoked 3 times with batches of 2 rows. Output shows the slice/batch structure so the two-level decomposition is visible.

## Picking the numbers

- **`slice_size:`** — bigger is better up to a point. Too small means high coordination overhead (more workers, more IPC). Too big means uneven load (one slow worker holds up the import). 10k–100k rows per slice is the sweet spot for most workloads.
- **`chunk_size:`** — DB-driven. Tune to your `insert_all` performance. Postgres handles ~500–1000 row batches well; MySQL similar. SQLite is slower. Test it.

A rough mental model: **`slice_size` × num_workers ≈ total_rows**, and **chunk_size is whatever your DB likes**.

## Caveats

- **`chunk_size:` is per-worker.** Each worker yields its own batches; batches don't span slices. If `slice_size: 50_000` and `chunk_size: 500`, you get exactly 100 batches per worker.
- **The block-vs-array distinction.** If you call `SmarterCSV.process_slice(slice) { |batch| ... }` (block), batches are yielded. If you call it without a block (`rows = SmarterCSV.process_slice(slice)`), `chunk_size:` causes the return value to be `Array<Array<Hash>>` (an array of batches). Either form works; pick whichever matches your downstream code.

## See also

- `../sidekiq/` — wires the worker side into Sidekiq jobs.
- `../parallel_gem/` — wires the worker side into forked processes.
- `../chunks_only/` — what you had before slicing existed; useful to compare and understand the upgrade.
- `docs/parallel_slicing.md` "Two row-count knobs" — the canonical reference for the two options.
