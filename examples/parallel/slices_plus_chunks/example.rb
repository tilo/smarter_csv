#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Slices + chunks combined — the production sweet spot.
#   - slice_size  controls work distribution (one slice per worker)
#   - chunk_size  controls batch granularity within each worker (one batch per DB insert)
# Run: bundle exec ruby examples/parallel/slices_plus_chunks/example.rb

require 'smarter_csv'
require 'tempfile'

SAMPLE_CSV = <<~CSV
  a,b,c,d
  1,2,3,4
  5,6,7,8,extra1
  9,10,11,12
  13,14,15,16,extra2,extra3
  17,18,19,20
  21,22,23,24,extra4
  25,26,27,28
  29,30,31,32,extra5,extra6,extra7,extra8
  33,34,35,36
  37,38,39,40,,,,sparse
  41,42,43,44,extra9
  45,46,47,48
CSV

Tempfile.create(['slices_plus_chunks_demo', '.csv']) do |f|
  f.write(SAMPLE_CSV)
  f.flush

  # slice_size = 6  → 2 slices of 6 rows each (work distribution unit, would be a worker each)
  # chunk_size = 2  → within each slice, the block yields batches of 2 rows (DB-insert unit)
  slices = SmarterCSV.slice(f.path, slice_size: 6, chunk_size: 2)
  puts "Sliced #{slices.size} slices (slice_size: 6); each worker yields batches (chunk_size: 2)."
  puts ""

  slices.each do |slice|
    puts "--- Slice row_offset=#{slice[:row_offset]} ---"
    batch_count = 0
    SmarterCSV.process_slice(slice) do |batch|
      batch_count += 1
      puts "  Batch #{batch_count} (#{batch.size} rows) — would be one Model.insert_all() call:"
      batch.each { |row| puts "    #{row.inspect}" }
    end
    puts "  → Slice yielded #{batch_count} batches total."
  end
end
