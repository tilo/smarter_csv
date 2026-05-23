#!/usr/bin/env ruby
# frozen_string_literal: true
#
# In-process serial loop — the simplest deployment of slice-mode processing.
# Run: bundle exec ruby examples/parallel/serial_loop/example.rb

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

Tempfile.create(['serial_loop_demo', '.csv']) do |f|
  f.write(SAMPLE_CSV)
  f.flush

  slices = SmarterCSV.slice(f.path, slice_size: 4)
  puts "Sliced #{slices.size} slices of up to 4 rows each."
  puts ""

  slices.each do |slice|
    puts "--- Slice row_offset=#{slice[:row_offset]} (bytes #{slice[:from_byte]}..#{slice[:to_byte]}) ---"
    SmarterCSV.process_slice(slice).each_with_index do |row, i|
      global_row = slice[:row_offset] + i
      puts "  global row #{global_row.to_s.rjust(2)}: #{row.inspect}"
    end
  end
end
