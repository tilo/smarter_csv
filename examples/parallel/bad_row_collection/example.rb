#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Bad-row collection across slices: each worker uses on_bad_row: :collect to gather bad rows
# locally; the aggregator collects them into a unified audit record.
# Run: bundle exec ruby examples/parallel/bad_row_collection/example.rb

require 'smarter_csv'
require 'tempfile'

# Mixed-validity CSV: header declares 4 columns, but some data rows have extras. With
# missing_headers: :raise these wider rows trigger HeaderSizeMismatch; on_bad_row: :collect
# captures them as bad-row records instead of aborting the import.
SAMPLE_CSV = <<~CSV
  id,name,email,country
  1,Alice,alice@example.com,US
  2,Bob,bob@example.com,UK,SURPRISE_EXTRA_COL
  3,Carol,carol@example.com,US
  4,Dave,dave@example.com,DE,extra1,extra2
  5,Eve,eve@example.com,FR
  6,Frank,frank@example.com,UK
  7,Grace,grace@example.com,US,UNEXPECTED
  8,Heidi,heidi@example.com,FR
  9,Ivan,ivan@example.com,US
  10,Judy,judy@example.com,UK
CSV

Tempfile.create(['bad_row_demo', '.csv']) do |f|
  f.write(SAMPLE_CSV)
  f.flush

  slices = SmarterCSV.slice(f.path, slice_size: 3, missing_headers: :raise, on_bad_row: :collect)
  puts "Processing #{slices.size} slices with missing_headers: :raise + on_bad_row: :collect..."
  puts ""

  per_slice_audit = slices.map do |slice|
    reader = SmarterCSV::Reader.new(slice[:input], slice[:options])
    rows = reader.process_slice(slice)
    {
      row_offset:    slice[:row_offset],
      good_rows:     rows.size,
      bad_rows:      reader.errors[:bad_rows] || [],
      bad_row_count: reader.errors[:bad_row_count] || 0,
    }
  end

  per_slice_audit.each do |s|
    puts "Slice row_offset=#{s[:row_offset]}: #{s[:good_rows]} good, #{s[:bad_row_count]} bad"
    s[:bad_rows].each do |err|
      puts "  bad row at csv_line_number=#{err[:csv_line_number]}: #{err[:error_class]} — #{err[:error_message]}"
    end
  end

  # Aggregator-side: union all bad rows into one audit record, anchored on slice[:row_offset]
  total_good = per_slice_audit.sum { |s| s[:good_rows] }
  total_bad  = per_slice_audit.sum { |s| s[:bad_row_count] }
  all_bad_rows = per_slice_audit.flat_map { |s|
    s[:bad_rows].map { |err| err.merge(global_row: s[:row_offset] + (err[:csv_line_number] || 0)) }
  }

  puts ""
  puts "AUDIT:"
  puts "  total good rows:    #{total_good}"
  puts "  total bad rows:     #{total_bad}"
  puts "  bad rows by global position:"
  all_bad_rows.each do |err|
    puts "    global_row=#{err[:global_row]}: #{err[:error_class]} (#{err[:error_message]})"
  end
end
