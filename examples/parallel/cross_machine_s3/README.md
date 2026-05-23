# Cross-machine slicing — S3-backed sources

The byte-range slice descriptors that work over a local file also work over S3. Producer downloads the file once to slice it; workers (on potentially different machines) each fetch only their slice's bytes via S3 Range requests.

This unlocks **multi-machine parallelism**: workers can live in different Kubernetes pods, different EC2 instances, different regions — wherever your job queue dispatches them. The source file stays in S3; nobody downloads it whole except the producer.

## When to use this

- **Multi-tenant SaaS imports.** Customer uploads CSV to your S3 bucket; workers across your fleet process it. Workers don't need to know which fleet they're on — they just need S3 read access.
- **Files too large for any single machine's disk.** A 100GB CSV won't fit on a small worker's local disk, but each worker only needs its slice (~1GB for 100 slices).
- **Decoupling storage from compute.** Source CSVs in S3 stay there; workers are stateless and can be auto-scaled.
- **Hybrid deployments** — some workers on-premises, some in cloud, all reading from a shared S3 source.

## Required gem

```
gem install aws-sdk-s3
```

For real S3: AWS credentials (IAM role, env vars, or credentials file).

The example uses stub functions (`fake_download_from_s3`, `fake_s3_get_object_range`) so it runs without AWS. The code shape is what you'd write for real; swap stubs for `Aws::S3::Client` calls.

## The pattern

### Producer side

```ruby
client = Aws::S3::Client.new

# Download the file once for slicing — slicer needs the whole file for the quote-aware scan
Tempfile.create(['s3_input', '.csv']) do |local|
  client.get_object(bucket: bucket, key: key, response_target: local.path)
  slices = SmarterCSV.slice(local.path, slice_size: 50_000, chunk_size: 500)

  # Rewrite slice[:input] to point at S3 (the byte offsets still apply)
  slices.map { |s| s.merge(input: "s3://#{bucket}/#{key}", bucket: bucket, key: key) }
end
```

### Worker side

```ruby
client = Aws::S3::Client.new
response = client.get_object(
  bucket: slice[:bucket],
  key:    slice[:key],
  range:  "bytes=#{slice[:from_byte]}-#{slice[:to_byte] - 1}",
)

# Write the bytes to a local tempfile and process
Tempfile.create(['s3_slice', '.csv']) do |local|
  local.write(response.body.read)
  local.flush
  local_slice = slice.merge(input: local.path, from_byte: 0, to_byte: local.size)
  SmarterCSV.process_slice(local_slice) do |batch|
    Model.insert_all(batch)
  end
end
```

The `Range: bytes=N-M` HTTP header is part of the standard S3 GetObject API — no special features needed. Inclusive on both ends in the HTTP semantics; SmarterCSV's `to_byte` is exclusive, hence the `- 1`.

## What the demo prints

The standalone example uses stub S3 functions backed by an in-memory CSV. The structure mirrors production: producer downloads, slices, emits S3-pointing slices; workers fetch their byte range via the (faked) `get_object(range:)` and process locally. Output shows the slice/byte-range/row-count breakdown per worker.

## Production deployment notes

- **The producer downloads the file once.** This is the only full-file read. After slicing, that local copy can be deleted; workers re-fetch only their slice from S3.
- **Workers don't share state across machines.** Each worker is independently authenticated to S3 (via its own IAM role or credentials), independently fetches its range, independently writes results. No coordination beyond the slice payload.
- **Eventual consistency.** S3 is strongly consistent for reads after upload (since 2020), so all workers see the same bytes at the same offsets. The slicer's byte ranges remain valid as long as the source S3 object isn't replaced.
- **Cost.** Each worker's S3 GET costs ~$0.0004 per 1000 requests + bandwidth. For 100-slice imports, GET cost is negligible; bandwidth is the same total as one full download but distributed across workers.
- **Bandwidth.** Each worker pulls `total_bytes / num_workers` from S3 (roughly). For 8 workers and a 100GB file, each pulls ~12.5GB. Within the same AWS region, bandwidth is fast and free.

## Caveats

- **Producer + worker need to share the SmarterCSV version.** They both invoke the slicer/process_slice machinery; mismatched versions could mean different slice descriptor shapes or different parser behavior.
- **The slice descriptor is small** (a few hundred bytes), so shipping it through Sidekiq/SQS/whatever is cheap regardless of how big the source file is.
- **For S3 objects WITH server-side compression or encryption,** Range requests still work but the byte ranges in your slice descriptors correspond to the *decoded* file, not the encoded one. If your CSV is gzipped on S3, you can't Range-fetch — gzip isn't seekable. Decompress to a non-compressed S3 object first, or stage locally.
- **Cross-region transfers cost.** If workers are in us-east-1 and the S3 bucket is in eu-west-1, you pay cross-region bandwidth on every slice fetch.

## See also

- `../sidekiq/` — pair this with Sidekiq for cross-host worker distribution.
- `../sidekiq_db_table/` or `../sidekiq_redis_counter/` — for per-worker output persistence when workers are on different machines.
- `docs/parallel_slicing.md` "Cross-machine workers, shared S3 file" — the doc this implements.
