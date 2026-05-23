#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Parallel validation: workers checksum / validate their slice (no DB write); parent collects
# pass/fail per slice. Slicing as a validation primitive, not an import primitive.
# Run: gem install parallel && bundle exec ruby examples/parallel/parallel_validation/example.rb

require 'smarter_csv'
require 'parallel'
require 'digest'
require 'tempfile'

abort 'Parallel.map requires fork — POSIX only (not supported on Windows).' if Gem.win_platform?

SAMPLE_CSV = <<~CSV
  id,name,email
  1,Alice,alice@example.com
  2,Bob,bob@example.com
  3,Carol,carol@example.com
  4,Dave,
  5,Eve,eve@example.com
  6,Frank,frank@example.com
  7,Grace,grace@example.com
  8,Heidi,heidi@example.com
  9,Ivan,
  10,Judy,judy@example.com
  11,Mallory,mallory@example.com
  12,Niaj,niaj@example.com
CSV

Tempfile.create(['parallel_validation_demo', '.csv']) do |f|
  f.write(SAMPLE_CSV)
  f.flush

  slices = SmarterCSV.slice(f.path, slice_size: 4)
  puts "Validating #{slices.size} slices in parallel (#{Parallel.processor_count} workers max)..."
  puts ""

  results = Parallel.map(slices, in_processes: [slices.size, Parallel.processor_count].min) do |slice|
    rows = SmarterCSV.process_slice(slice)

    bad_rows = rows.each_with_index.select { |row, _| row[:email].nil? || row[:email].empty? }
    checksum = Digest::SHA256.hexdigest(rows.map(&:to_s).join("\n"))

    {
      row_offset:    slice[:row_offset],
      row_count:     rows.size,
      bad_row_count: bad_rows.size,
      bad_row_local_offsets: bad_rows.map { |_, i| i },
      checksum:      checksum,
    }
  end

  results.sort_by { |r| r[:row_offset] }.each do |r|
    status = r[:bad_row_count].zero? ? 'OK' : "FAIL (#{r[:bad_row_count]} missing email)"
    puts "  slice row_offset=#{r[:row_offset]}: #{r[:row_count]} rows, #{status}, checksum=#{r[:checksum][0..7]}..."
    r[:bad_row_local_offsets].each do |local_i|
      puts "    bad row at global offset #{r[:row_offset] + local_i}"
    end
  end

  total_bad = results.sum { |r| r[:bad_row_count] }
  puts ""
  puts "Validation summary: #{total_bad} bad rows across #{slices.size} slices."
  puts "Decision: #{total_bad.zero? ? 'PROCEED with import' : 'REJECT — fix the source file first'}"
end
