#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Parallel.each with per-slice tempfiles — the realistic "side-effect workflow" shape. Workers
# write to per-slice tempfiles (stand-in for DB inserts); parent reads them after.
# Run: gem install parallel && bundle exec ruby examples/parallel/parallel_each_tempfiles/example.rb

require 'smarter_csv'
require 'parallel'
require 'json'
require 'tempfile'

abort 'Parallel.each requires fork — POSIX only.' if Gem.win_platform?

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

Tempfile.create(['parallel_each_input', '.csv']) do |input|
  input.write(SAMPLE_CSV)
  input.flush

  slices = SmarterCSV.slice(input.path, slice_size: 4)

  Dir.mktmpdir do |dir|
    puts "Workers write per-slice JSONL tempfiles to #{dir} (stand-in for DB inserts)..."
    puts ""

    Parallel.each(slices, in_processes: [slices.size, Parallel.processor_count].min) do |slice|
      out_path = File.join(dir, format("slice_%010d.jsonl", slice[:row_offset]))
      File.open(out_path, 'w') do |f|
        SmarterCSV.process_slice(slice) do |batch|
          # In production: Model.insert_all(batch). For this demo: append each row as JSONL.
          batch.each { |row| f.puts JSON.generate(row) }
        end
      end
      # No return value — Parallel.each doesn't Marshal anything back to parent. The side effect
      # (the tempfile) is the output.
    end

    puts "Parent now reads per-slice tempfiles in row_offset order (encoded in filenames):"
    Dir.glob(File.join(dir, 'slice_*.jsonl')).sort.each do |path|
      row_offset = File.basename(path)[/\d+/].to_i
      lines = File.readlines(path, chomp: true)
      puts "  slice row_offset=#{row_offset}: #{lines.size} rows from #{File.basename(path)}"
      lines.each_with_index do |line, i|
        puts "    global_row=#{row_offset + i}: #{JSON.parse(line, symbolize_names: true).inspect}"
      end
    end
  end
end
