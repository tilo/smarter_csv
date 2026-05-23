# Chunks only — the pre-1.18.0 baseline

`SmarterCSV.process(path, chunk_size: N)` parses the whole file sequentially in one process, yielding batches of N rows to the block. Parallelism (if any) lives on the consumer side: hand each batch off to a Sidekiq job, an `insert_all`, an external service, etc.

This is what users did before slice mode existed (1.17.0 and earlier) and what most production code still does.

## When this is enough

- **DB-write bound, not parse-bound.** If your bottleneck is `Model.insert_all(batch)` (index maintenance, lock contention), and parsing the CSV is the cheap part, chunks-only is perfectly fine. Slicing parallelizes the parse — but the parse wasn't the slow part to begin with.
- **Small to mid files** (under ~1M rows). The fixed cost of slicing's quote-aware scan + worker dispatch isn't paid back by the parallelism win at this size.
- **Single-machine deployments** where you'd just push chunks to Sidekiq one machine over and don't need multi-worker parsing.

## When to upgrade to slicing

- **Multi-million-row files** where parsing time becomes meaningful relative to DB writes.
- **CPU-heavy parsing** — lots of `value_converters`, complex `hash_transformations`, large rows with many columns.
- **Multi-core machines you want to actually use.** With chunks-only, the producer is single-threaded and pegs one CPU at 100%. With slicing, you can parse on N cores.

See `../slices_plus_chunks/` for the combined approach — slice for parsing parallelism, chunks for batched DB writes inside each worker.

## The code

```ruby
SmarterCSV.process(path, chunk_size: 500) do |batch, chunk_index|
  Model.insert_all(batch)              # in-process serial
  # or:
  # ImportChunkJob.perform_async(batch) # consumer parallelism via Sidekiq
end
```

## What the demo prints

A 12-row mixed-width CSV gets parsed end-to-end in the producer process, yielding 3 batches of up to 4 rows each. The output shows each chunk's contents — same row hashes as you'd get from slicing, but produced by one sequential pass.

## Caveats

- **No `slice[:row_offset]` anchor.** If you need global row numbers, track them yourself (`global_idx = chunk_index * chunk_size + i`). Slice mode hands you this for free.
- **Producer is single-threaded.** Even if you fan chunks out to Sidekiq, parsing on a busy machine will be parse-CPU-bound on one core.
- **Memory grows with chunk_size.** Each batch holds N parsed Hashes. Memory bounded but not tiny.

## See also

- `../serial_loop/` — slice-mode equivalent of this pattern, but each "chunk" is a slice the worker re-parses (so parsing is restartable per-slice).
- `../slices_plus_chunks/` — combined approach: slicing for work distribution, chunks within each worker.
- `docs/batch_processing.md` — the canonical chunked-processing reference.
