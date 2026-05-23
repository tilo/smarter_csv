# Parallel CSV processing — examples

This directory holds runnable examples demonstrating the different patterns for parallel CSV processing with SmarterCSV. Each subdirectory is one self-contained example: a `README.md` explaining the pattern + an `example.rb` that runs it. CSV fixtures used across multiple examples live in `../fixtures/`.

## Mental model

Two distinct approaches to parallelism:

- **Chunks** (`SmarterCSV.process(path, chunk_size: N)`) — sequential parse on the producer side, parallelism only on the consumer side. The producer reads the CSV linearly and hands out batches of pre-parsed row hashes to workers. The pre-1.18.0 way. See [docs/batch_processing.md](../../docs/batch_processing.md).
- **Slices** (`SmarterCSV.slice` + `SmarterCSV.process_slice`) — workers parse their own bytes. The producer does one cheap quote-aware scan emitting byte-range references; each worker `seek`s into the source file and parses only its slice. Parallelism on both producer and consumer sides. Available in 1.18.0+. See [docs/parallel_slicing.md](../../docs/parallel_slicing.md).
- **Combined** — slice for work distribution, `chunk_size:` within each worker for batched DB writes. The pattern most production users want.

## Tranches

Examples are grouped into three priority tranches by usefulness. Within each tranche, examples are independent of each other and can be read in any order.

- **Tranche 1 — Canonical 5** — covers ~80% of real use cases. Start here.
- **Tranche 2 — Sidekiq production patterns** — what you build when going from prototype to production.
- **Tranche 3 — Beyond DB import** — slicing's generality (validation, filtering, map-reduce) and platform variants (GoodJob, Solid Queue, S3, manual `fork`).

## Tranche 1 — Canonical patterns (5)

| Name                 | Pattern                                                                                                                            | Currently exists as                                              | Gems required               |
| -------------------- | ---------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------- | --------------------------- |
| `serial_loop`        | Single-process serial loop: `slices.each { \|s\| SmarterCSV.process_slice(s) }`. The simplest deployment.                           | `spec/features/serial_slicing_spec.rb`                           | (none beyond smarter_csv)   |
| `parallel_gem`       | `Parallel.map` forked workers (POSIX). True CPU parallelism via process fork. Results Marshaled back to parent.                     | `spec/features/parallel_gem_slicing_spec.rb`                     | `parallel`                  |
| `sidekiq`            | Sidekiq worker pattern with shared store + `deep_symbolize_keys` (recovers symbol keys after Sidekiq's JSON roundtrip).             | `spec/features/sidekiq_slicing_spec.rb`                          | `sidekiq`, `activesupport`  |
| `chunks_only`        | Pre-1.18.0 baseline — `SmarterCSV.process(path, chunk_size: N) { \|batch\| ... }`. Sequential parse, hand batches off to workers.   | New                                                              | (none)                      |
| `slices_plus_chunks` | Slicing + `chunk_size:` combined — slice for work distribution, chunk for batched DB writes within each worker. Production sweet spot. | New                                                              | (any queue framework you use) |

## Tranche 2 — Sidekiq production patterns (4)

| Name                    | Pattern                                                                                                                              | Currently exists as                       | Gems required                |
| ----------------------- | ------------------------------------------------------------------------------------------------------------------------------------ | ----------------------------------------- | ---------------------------- |
| `sidekiq_aggregator`    | Fan-in: a separate `AggregateResultsJob` runs after all slice jobs finish; reads the shared store; builds unified headers/warnings/errors. | Documented in `docs/parallel_slicing.md`  | `sidekiq`, `activesupport`   |
| `sidekiq_retry`         | Idempotent worker via `upsert_all`. Slice raises once, gets re-enqueued by Sidekiq, succeeds on retry — no double-insert, no lost rows. | Documented in `docs/parallel_slicing.md`  | `sidekiq`, `activesupport`   |
| `sidekiq_db_table`      | Aggregation via a `SliceResult` ActiveRecord table (Pattern 1 from the docs). Durable, queryable, Rails-idiomatic.                  | Documented in `docs/parallel_slicing.md`  | `sidekiq`, `activerecord`    |
| `sidekiq_redis_counter` | Aggregation via Redis hash + atomic `DECR` counter (Pattern 2 from the docs). No DB schema; OSS Sidekiq (no Pro needed).             | Documented in `docs/parallel_slicing.md`  | `sidekiq`                    |

## Tranche 3 — Beyond DB import (9)

| Name                      | Pattern                                                                                                                                                       | Currently exists as | Gems required                       |
| ------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------- | ----------------------------------- |
| `parallel_validation`     | Workers compute a per-slice checksum or pass-fail (no DB write). Parent collects pass/fail. Useful for "is this file healthy enough to import?" pre-checks.    | New                 | `parallel`                          |
| `parallel_filtering`      | Each worker writes filtered output to a per-slice tempfile; parent concatenates into one filtered CSV. Demonstrates slicing for CSV-to-CSV transforms.        | New                 | `parallel`                          |
| `map_reduce_aggregation`  | Workers compute partial aggregates (sum, count, distinct) over their slice; reducer combines into a final analytics row. Slicing as a map-reduce primitive.    | New                 | `parallel`                          |
| `cross_machine_s3`        | S3-backed: producer slices an S3 object; workers `get_object(range:)` from different hosts. Same byte-range slice descriptors, multi-machine deployment.        | New                 | `aws-sdk-s3`                        |
| `progress_reporting`      | Workers report per-slice progress via Statsd/Prometheus/DB row using `slice[:row_offset]` as the global anchor. Lifecycle visibility for long-running imports. | New                 | `sidekiq`, (statsd / prometheus)    |
| `bad_row_collection`      | `on_bad_row: :collect` per slice; aggregator combines errors into a final audit record. The "import succeeded but here's what we skipped" workflow.            | New                 | `sidekiq`, `activesupport`          |
| `manual_fork`             | Bare `Process.fork` + `Process.wait`. No gems, no framework. Shows what `parallel` does under the hood. Educational; not for production.                       | New                 | (none)                              |
| `goodjob` / `solid_queue` | Same worker shape as Sidekiq, different queue framework. Demonstrates that the slice-mode pattern is queue-backend-agnostic.                                   | New                 | `goodjob` *or* `solid_queue`        |
| `parallel_each_tempfiles` | Variant: `Parallel.each` (not `.map`) with workers writing per-slice tempfiles, parent reads them after. Closer to a real Rails import doing `insert_all`.    | Test coverage in `spec/features/parallel_gem_slicing_spec.rb` (the third example) | `parallel`                          |

## Considered but out of scope

Approaches we evaluated and decided not to pursue, with reasoning so readers don't have to rediscover the same paths:

- **Pipe-scatter** — non-seekable inputs handled via row-level round-robin over N forked pipes. Real systems engineering (managing N pipes, EOF handshakes, child-exception propagation); plausible PRO / commercial add-on. See `parallel_processing_csv_files.md` for the full design.
- **Ractors** — Rails/ActiveRecord is not Ractor-safe (workers can't write to the DB). Also non-shareable objects are Marshal-copied across Ractor boundaries, so no advantage over `fork` for shipping parsed rows.
- **Threads + GVL-releasing C** — hash construction needs the GVL, so threads serialize on it. Ceiling ~1.5–3× for CSV parsing, not the order-of-magnitude path.
- **Async / Falcon / fibers** — M:N scheduling doesn't remove the GVL. Helps I/O-bound code; nothing for CPU-bound CSV parsing.
- **Marshal+Base64 for IPC** — brittle across Ruby major versions, ~33% size overhead. Use Oj/JSON + `deep_symbolize_keys` + targeted normalization instead. See the Tranche 1 `sidekiq` example for the canonical pattern.

## How to read each example

Each subdirectory contains:

- **`README.md`** — the pattern explained: what problem it solves, when to use it, what to watch out for, expected output. Read this first.
- **`example.rb`** — runnable Ruby. Self-contained: generates its own sample CSV inline, runs the pattern, prints what happened. No external fixtures or setup unless the example calls them out explicitly (e.g., the Sidekiq + real-Redis examples).

CSV fixtures shared across multiple examples (e.g., a mixed-width CSV demonstrating cross-slice synthetic column behavior) live in `../fixtures/`. Examples that need a unique fixture inline it in the `.rb` file rather than depending on a separate fixture file.

## Related documentation

- [`docs/parallel_slicing.md`](../../docs/parallel_slicing.md) — slicing API reference, aggregation patterns, when slicing wins, caveats
- [`docs/batch_processing.md`](../../docs/batch_processing.md) — chunked processing (the pre-1.18.0 approach)
- [`docs/parallel_processing.md`](../../docs/parallel_processing.md) *(forthcoming)* — top-level overview comparing chunks vs. slices vs. combined; this README's higher-level companion
