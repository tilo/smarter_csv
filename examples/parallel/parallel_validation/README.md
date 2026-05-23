# Parallel validation — slicing for "is this file healthy?"

Slicing isn't only for imports. The same byte-range parallelism that distributes parse work also distributes **validation** work: each worker checks its slice for problems (missing fields, invalid formats, duplicate IDs, checksums) and returns pass/fail. The parent collects results to decide "proceed with import" vs "reject this upload."

## When to use this

- **Pre-import sanity checks.** Before committing to a multi-million-row insert, run a parallel validation pass. Cheaper than starting and rolling back.
- **Continuous data quality monitoring.** Periodic validation runs on inbound files; alerts on threshold violations.
- **Checksum verification for large files.** Parallelize the integrity check across slices.
- **Duplicate detection** within a file — workers hash keys, parent finds collisions.

The pattern works because validation is naturally parallelizable: each row is checked independently. The slicer provides the work distribution; workers do the per-row checks.

## Required gem

```
gem install parallel
```

## The code

```ruby
results = Parallel.map(slices, in_processes: 8) do |slice|
  rows     = SmarterCSV.process_slice(slice)
  bad_rows = rows.each_with_index.select { |row, _| !valid?(row) }
  {
    row_offset:    slice[:row_offset],
    row_count:     rows.size,
    bad_row_count: bad_rows.size,
    checksum:      Digest::SHA256.hexdigest(rows.map(&:to_s).join("\n")),
  }
end

total_bad = results.sum { |r| r[:bad_row_count] }
if total_bad.zero?
  ImportJob.perform_async(file_path)
else
  ImportRejected.create!(reason: "#{total_bad} bad rows", details: results)
end
```

## What the demo prints

The example uses a 12-row CSV with 2 deliberately bad rows (missing email). Three slices of 4 rows each are validated in parallel. Output shows per-slice status (OK / FAIL with bad-row local offsets), the SHA256 checksum of each slice (for content-integrity verification across imports), and a final decision: proceed or reject.

## What to validate

Pick whatever matters for your data:

- **Required fields present** — `row[:email].nil? || row[:email].empty?`
- **Format checks** — emails parse, dates are valid, numbers are in range
- **Foreign key references resolve** — `Customer.exists?(customer_id: row[:customer_id])`
- **Domain rules** — `row[:total] == row[:subtotal] + row[:tax]`
- **Duplicate detection** — workers emit a set of keys; parent finds collisions across sets

For duplicate detection across slices, workers can't see each other's keys directly. Each worker returns its key set; the parent intersects them.

## Caveats

- **Checksum scope.** A per-slice checksum verifies that slice's content but doesn't verify the whole-file ordering. For whole-file integrity, hash the slices' checksums together: `Digest::SHA256.hexdigest(results.sort_by{|r|r[:row_offset]}.map{|r|r[:checksum]}.join)`.
- **Foreign key checks involve DB hits.** Each worker hitting the DB in parallel can overwhelm the connection pool. Either batch the lookups (one query per slice) or cap workers below the pool size.
- **Validation is read-only** — no `process_slice` side effects to roll back if you decide to reject the file. Pure pre-flight check.

## See also

- `../parallel_gem/` — same `Parallel.map` mechanics, different work (parse + insert vs. parse + validate).
- `../map_reduce_aggregation/` — similar pattern but workers compute aggregates, not just validations.
- `../bad_row_collection/` — for "import what you can, report what you couldn't" — captures bad rows during a real import rather than rejecting upfront.
