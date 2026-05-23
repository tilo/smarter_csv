#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Parallel filtering: each worker writes filtered rows to its own tempfile; parent concatenates
# in slice order. Demonstrates slicing for CSV-to-CSV transforms — extract a subset, reformat
# columns, redact PII, etc.
# Run: gem install parallel && bundle exec ruby examples/parallel/parallel_filtering/example.rb

require 'smarter_csv'
require 'parallel'
require 'tempfile'

abort 'Parallel.map requires fork — POSIX only (not supported on Windows).' if Gem.win_platform?

SAMPLE_CSV = <<~CSV
  id,name,country,score
  1,Alice,US,85
  2,Bob,UK,72
  3,Carol,US,91
  4,Dave,DE,68
  5,Eve,US,77
  6,Frank,UK,82
  7,Grace,US,88
  8,Heidi,FR,79
  9,Ivan,US,65
  10,Judy,UK,93
  11,Mallory,US,71
  12,Niaj,DE,84
CSV

# Filter: keep only US rows; redact name (initials only); add a derived column.
def keep?(row)
  row[:country] == 'US'
end

def transform(row)
  initials = row[:name].split(/[\s-]+/).map { |w| w[0] }.join('.')
  { id: row[:id], initials: initials, country: row[:country], score: row[:score], grade: row[:score] >= 85 ? 'A' : 'B' }
end

Tempfile.create(['parallel_filtering_input', '.csv']) do |input|
  input.write(SAMPLE_CSV)
  input.flush

  slices = SmarterCSV.slice(input.path, slice_size: 4)
  puts "Filtering #{slices.size} slices in parallel; each worker writes a per-slice tempfile."
  puts ""

  Dir.mktmpdir do |dir|
    Parallel.each(slices, in_processes: [slices.size, Parallel.processor_count].min) do |slice|
      out_path = File.join(dir, format("slice_%010d.csv", slice[:row_offset]))
      File.open(out_path, 'w') do |f|
        SmarterCSV.process_slice(slice) do |batch|
          batch.each do |row|
            next unless keep?(row)
            transformed = transform(row)
            f.puts transformed.values.join(',')
          end
        end
      end
      puts "  worker pid=#{Process.pid} wrote #{out_path} (#{File.size(out_path)} bytes)"
    end

    puts ""
    puts "Parent concatenates per-slice files in slice order (sorted by row_offset in the name):"
    final_path = File.join(dir, 'filtered_output.csv')
    File.open(final_path, 'w') do |out|
      out.puts %w[id initials country score grade].join(',')
      Dir.glob(File.join(dir, 'slice_*.csv')).sort.each do |slice_file|
        out.write(File.read(slice_file))
      end
    end

    puts ""
    puts "Final output:"
    puts File.read(final_path)
  end
end
