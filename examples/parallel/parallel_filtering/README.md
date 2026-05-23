# Parallel filtering — CSV-to-CSV transforms

Many "import" workflows are actually "transform" workflows: take a CSV, filter rows, reshape columns, redact PII, anonymize, and write a new CSV. Slicing parallelizes this naturally. Each worker reads its slice, filters/transforms, writes to a per-slice tempfile. The parent concatenates the tempfiles in slice order to produce the final output.

## When to use this

- **Subset extraction** — "give me only US rows from this 100GB file"
- **Column reshaping** — drop columns, add derived columns, rename headers
- **PII redaction** — replace names with initials, mask SSNs, hash emails
- **Format conversion** — parse JSON columns, normalize date formats, recompute totals
- **Anonymization pipelines** — produce a de-identified copy of a sensitive dataset
- **Pre-processing** — clean up a raw CSV before importing it elsewhere

The pattern works because filtering/transforming is row-local: each row's output depends only on that row's input. No cross-row dependencies (those would need `map_reduce_aggregation` instead).

## Required gem

```
gem install parallel
```

## The pattern

```ruby
slices = SmarterCSV.slice(input_path, slice_size: 50_000)

Dir.mktmpdir do |dir|
  Parallel.each(slices, in_processes: 8) do |slice|
    out_path = File.join(dir, format("slice_%010d.csv", slice[:row_offset]))
    File.open(out_path, 'w') do |f|
      SmarterCSV.process_slice(slice) do |batch|
        batch.each do |row|
          next unless keep?(row)
          f.puts transform(row).values.join(',')
        end
      end
    end
  end

  # Parent concatenates per-slice files, sorted by row_offset (encoded in filename)
  File.open(final_path, 'w') do |out|
    out.puts headers.join(',')
    Dir.glob(File.join(dir, 'slice_*.csv')).sort.each { |sf| out.write(File.read(sf)) }
  end
end
```

The filename trick (`slice_%010d.csv`) makes alphanumeric sort match row_offset order. Workers complete in arbitrary order; their filenames sort deterministically.

## What the demo prints

12 rows mixing US/UK/DE/FR countries. Filter keeps only `country: 'US'`, transforms `name` to `initials`, adds a `grade` column derived from `score`. Three slices process in parallel, each writes a slice file; parent concatenates. Final output is a CSV with header + filtered/transformed rows.

## Why `Parallel.each` not `Parallel.map`

For pure side-effect workflows (write to disk, write to DB), `Parallel.each` doesn't Marshal results back to the parent — saving the IPC cost. The parent reads side-effects from disk after `Parallel.each` returns. `Parallel.map` would force Marshaling each worker's parsed rows back to the parent, slow and unnecessary here.

## Caveats

- **Per-slice tempfiles need cleanup.** `Dir.mktmpdir` does this automatically when the block exits.
- **Slice-order preservation.** Workers complete in arbitrary order; their filenames encode `row_offset` so sorting alphabetically restores order. If you need true streaming output (no temp files), you'd need a synchronized writer — adds complexity.
- **Header line is written by the parent**, not by workers. Workers only write filtered data rows.
- **Errors per worker** are isolated — a worker raising doesn't kill the whole run by default; check `Parallel.each`'s error handling docs for stricter behavior.

## Variations

- **Multiple output files** — workers can write to different output files based on row content (one CSV per `country`, for example). Parent assembles per-country files.
- **Compressed output** — workers can write to `.gz` per-slice files; parent concatenates raw gzip streams (gzip-concatenable by design).
- **Stream to S3** — workers can upload per-slice files directly to S3 with a known key prefix; parent issues `aws s3 cp --recursive` or runs an aggregator.

## See also

- `../parallel_gem/` — base `Parallel.map` pattern with rows returned to parent.
- `../parallel_each_tempfiles/` — same per-slice-tempfile pattern but for "write to DB inside worker" workflows.
- `../map_reduce_aggregation/` — for transforms that DO have cross-row dependencies (aggregates, distinct counts).
