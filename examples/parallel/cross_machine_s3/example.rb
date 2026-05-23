#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Cross-machine slice processing with S3 as the source. Producer slices an S3 object; workers
# (possibly on different hosts) re-fetch their byte range via S3 Range requests.
#
# Run: this example is a SKETCH — it demonstrates the API shape but requires real AWS credentials
# and an S3 bucket to actually execute. Reading the file gives you the production pattern.

require 'smarter_csv'
require 'tempfile'

# Conceptual implementation. To actually run this against S3, install aws-sdk-s3, set
# credentials, replace MockS3Client with Aws::S3::Client.new, and uncomment the perform_async
# block to enqueue real Sidekiq jobs (with the worker also using aws-sdk-s3).

# === STAGE 1: producer side (single machine — typically a Rails background job) ===
# The producer downloads the S3 object once (so the slicer's quote-aware scan can read it),
# slices it, then emits slices that carry the S3 key and byte ranges. Slice payloads stay tiny
# (a few hundred bytes), so they ship through Sidekiq job args cleanly.

S3_BUCKET = 'my-imports'
S3_KEY    = 'uploads/customers-2026-05-16.csv'

def slice_s3_object(bucket:, key:)
  # The producer downloads the object once to slice it — needs the full bytes for the
  # quote-aware scan. Production: cache the file locally for the duration of slicing.
  Tempfile.create(['s3_input', '.csv']) do |local|
    # Production: client.get_object(bucket: bucket, key: key, response_target: local.path)
    fake_download_from_s3(bucket: bucket, key: key, to: local.path)

    slices = SmarterCSV.slice(local.path, slice_size: 50_000, chunk_size: 500)
    # Rewrite slice[:input] from the local tempfile to "s3://#{bucket}/#{key}" so workers know
    # where to fetch from. Slicer's byte offsets still apply — S3 Range requests use the same
    # byte coordinates as the local file did.
    slices.map { |s| s.merge(input: "s3://#{bucket}/#{key}", bucket: bucket, key: key) }
  end
end

# === STAGE 2: worker side (any machine with S3 access) ===
# Each worker pulls only its slice's byte range from S3 — no full-file download. The slice
# carries from_byte and to_byte; the worker requests Range: bytes=from_byte-to_byte-1 from S3.

def process_s3_slice(slice)
  bytes = fake_s3_get_object_range(
    bucket: slice[:bucket],
    key:    slice[:key],
    range:  "bytes=#{slice[:from_byte]}-#{slice[:to_byte] - 1}",
  )

  # Wrap bytes in a StringIO and adapt the slice for local processing. SmarterCSV.process_slice
  # currently reads from disk via slice[:input]; for S3 we hand it a StringIO directly through
  # the Reader API.
  bytes.force_encoding(slice[:options][:file_encoding] || 'UTF-8')

  # Build a Reader-style adapter for the byte payload (sketch — actual integration would either
  # extend SmarterCSV to accept an IO in process_slice or pre-stage bytes to a local tempfile).
  Tempfile.create(['s3_slice', '.csv']) do |local|
    local.write(bytes)
    local.flush
    local_slice = slice.merge(input: local.path, from_byte: 0, to_byte: bytes.bytesize)
    rows = SmarterCSV.process_slice(local_slice)
    # rows now has the parsed Hashes for THIS slice; do whatever — DB upsert, etc.
    rows.size
  end
end

# === Stubs for the demo — replace with real AWS SDK calls in production ===

DEMO_CSV = <<~CSV
  id,name,country
  1,Alice,US
  2,Bob,UK
  3,Carol,US
  4,Dave,DE
  5,Eve,FR
  6,Frank,UK
  7,Grace,US
  8,Heidi,FR
CSV

def fake_download_from_s3(bucket:, key:, to:)
  File.write(to, DEMO_CSV)
end

def fake_s3_get_object_range(bucket:, key:, range:)
  Tempfile.create(['fake_s3', '.csv']) do |f|
    f.write(DEMO_CSV)
    f.flush
    range_match = range.match(/bytes=(\d+)-(\d+)/)
    from = range_match[1].to_i
    to   = range_match[2].to_i
    File.open(f.path, 'rb') do |handle|
      handle.seek(from)
      return handle.read(to - from + 1)
    end
  end
end

# === Demo run ===

puts "Producer: downloading s3://#{S3_BUCKET}/#{S3_KEY} for slicing..."
slices = slice_s3_object(bucket: S3_BUCKET, key: S3_KEY)
puts "Producer: emitted #{slices.size} slices, each carrying the S3 key + byte range."
puts ""

puts "Worker(s): each fetches its slice via S3 Range request and processes."
slices.each_with_index do |slice, i|
  row_count = process_s3_slice(slice)
  puts "  worker #{i}: fetched bytes=#{slice[:from_byte]}-#{slice[:to_byte] - 1}, processed #{row_count} rows"
end

puts ""
puts "In production: workers are on different hosts; each makes its own S3 Range request. No"
puts "full-file download per worker — only the slice's bytes. Bandwidth scales linearly with"
puts "worker count (each gets ~total_bytes / num_workers from S3)."
