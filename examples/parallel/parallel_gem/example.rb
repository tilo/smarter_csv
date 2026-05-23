#!/usr/bin/env ruby
# frozen_string_literal: true
#
# In-process parallel slice processing via the `parallel` gem (forked workers, POSIX).
# Run: gem install parallel && bundle exec ruby examples/parallel/parallel_gem/example.rb
#
# POSIX-only: requires fork. Will exit on Windows.

require 'smarter_csv'
require 'parallel'
require 'tempfile'

abort 'Parallel.map requires fork — POSIX only (not supported on Windows).' if Gem.win_platform?

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

Tempfile.create(['parallel_gem_demo', '.csv']) do |f|
  f.write(SAMPLE_CSV)
  f.flush

  slices = SmarterCSV.slice(f.path, slice_size: 4)
  puts "Producer sliced #{slices.size} slices; dispatching to #{[slices.size, Parallel.processor_count].min} forked workers..."
  puts ""

  # Parallel.map: workers process in parallel, results are Marshaled back to the parent in input
  # order. Each worker returns the parsed rows for its slice.
  results = Parallel.map(slices, in_processes: [slices.size, Parallel.processor_count].min) do |slice|
    rows = SmarterCSV.process_slice(slice)
    # Workers in production would do Model.insert_all(rows) here. For the demo we return the rows
    # so the parent can verify cross-process correctness.
    { pid: Process.pid, row_offset: slice[:row_offset], rows: rows }
  end

  results.each do |r|
    puts "--- Worker pid=#{r[:pid]} processed slice row_offset=#{r[:row_offset]} (#{r[:rows].size} rows) ---"
    r[:rows].each_with_index do |row, i|
      puts "  global row #{(r[:row_offset] + i).to_s.rjust(2)}: #{row.inspect}"
    end
  end

  puts ""
  puts "Total rows across all workers: #{results.sum { |r| r[:rows].size }}"
end
