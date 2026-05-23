#!/usr/bin/env ruby
# frozen_string_literal: true
#
# The pre-1.18.0 way: SmarterCSV.process with chunk_size, no slicing. Sequential parse,
# parallelism (if any) happens on the consumer side only.
# Run: bundle exec ruby examples/parallel/chunks_only/example.rb

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

Tempfile.create(['chunks_only_demo', '.csv']) do |f|
  f.write(SAMPLE_CSV)
  f.flush

  puts "Processing whole file sequentially, yielding batches of chunk_size: 4..."
  puts ""

  chunk_count = 0
  SmarterCSV.process(f.path, chunk_size: 4) do |batch, chunk_index|
    chunk_count += 1
    puts "--- Chunk #{chunk_index} (#{batch.size} rows) ---"
    batch.each_with_index do |row, i|
      # Note: no slice[:row_offset] anchor here. We'd track our own global row counter if we
      # wanted to know "which row of the original CSV is this?"
      puts "  #{row.inspect}"
    end
    # In a real importer, the block body would be:
    #   ImportChunkJob.perform_async(batch)
    # — that's how you get parallelism: fan out the chunks. But parsing is still single-threaded
    # in the producer (this loop), no matter how many workers consume the chunks.
  end

  puts ""
  puts "Yielded #{chunk_count} chunks total. Parsing was 100% sequential in this process."
end
