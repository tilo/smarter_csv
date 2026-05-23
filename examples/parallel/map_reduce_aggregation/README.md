# Map-reduce aggregation — slicing as a parallel analytics primitive

Workers compute **partial aggregates** over their slice (sums, counts, distinct sets, max/min); the parent **reduces** the partials into the final aggregate. Classic map-reduce shape, with `SmarterCSV.slice` providing the work distribution.

This is slicing's value beyond imports: any aggregation that's commutative + associative (sum, count, max, min, distinct union) parallelizes cleanly. Each worker's partial is a tiny summary; reducing them is fast even if there are many slices.

## When to use this

- **Pre-computed analytics on uploaded CSVs.** "Show me total sales by currency, distinct customer count, max order" — fast even on huge files.
- **Pre-import statistics.** Before importing, summarize the file: row count, distinct values per column, value ranges. Useful for sanity-checking the upload.
- **Sampling-free counting.** Some count distinct queries are too slow in SQL after import; pre-compute them at parse time.
- **Histograms / bucketing.** Workers tally counts per bucket; reducer sums per-bucket counts across slices.

## What aggregates parallelize cleanly

- **Sum** — `partials.sum { |p| p[:total] }`
- **Count** — same
- **Max / min** — `partials.map { |p| p[:max] }.max`
- **Distinct set** — union of per-slice Sets
- **Histograms** — per-bucket sums across slices
- **Top-N** — heap-merge of per-slice top-Ns

## What doesn't parallelize cleanly (without more work)

- **Median / percentiles** — need the full sorted distribution, not just per-slice sorts. Approximate algorithms (t-digest) help.
- **Distinct count over very large sets** — exact distinct count means union of huge sets across slices, memory-heavy. HyperLogLog approximations are the standard answer.
- **Cross-row joins or correlations** — a row in slice A relating to a row in slice B doesn't work without a second pass.

## Required gem

```
gem install parallel
```

## The pattern

```ruby
# MAP: workers compute partial aggregates
partials = Parallel.map(slices, in_processes: 8) do |slice|
  rows = SmarterCSV.process_slice(slice)
  {
    total_by_currency: rows.group_by { |r| r[:currency] }.transform_values { |rs| rs.sum { |r| r[:amount] } },
    distinct_customers: rows.map { |r| r[:customer_id] }.to_set,
    max_amount: rows.map { |r| r[:amount] }.max,
  }
end

# REDUCE: combine partials
total_by_currency  = partials.each_with_object(Hash.new(0.0)) { |p, acc|
                       p[:total_by_currency].each { |k, v| acc[k] += v }
                     }
distinct_customers = partials.flat_map { |p| p[:distinct_customers].to_a }.uniq
max_amount         = partials.map { |p| p[:max_amount] }.max
```

## What the demo prints

The example uses an order-book-style CSV with 12 rows across 4 currencies and 5 customers. Three slices map in parallel; each prints its partial aggregates. Then the reducer combines: total sales by currency across all slices, orders by country, distinct customer IDs, max single-order amount.

## Caveats

- **Partial size matters.** Each partial gets Marshaled back to the parent (via `Parallel.map`). Tiny partials (a few Hashes/Sets) are essentially free; if your partial includes lists of all rows, you've defeated the point — you're just doing parallel parsing + serial accumulation. Keep partials small and dense.
- **Set union memory.** A Set of 100M distinct customer IDs is large. Either use HyperLogLog (`hll` gem) for approximate distinct counts, or partition by hash (rows for customer ID modulo N go to slice N) and union without overlap.
- **Float precision** in sums. For currency totals across millions of rows, floating-point can drift. Use integer cents or BigDecimal if exactness matters.

## See also

- `../parallel_gem/` — base `Parallel.map` pattern; same fan-out, different work (parse + insert vs. parse + aggregate).
- `../parallel_validation/` — similar shape but workers do pass/fail checks, not numeric aggregation.
- `../parallel_filtering/` — for row-local transforms with no aggregation.
