#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Progress reporting: per-slice progress published to a shared sink (stdout in the demo;
# Statsd/Prometheus/DB row in production). Uses slice[:row_offset] + local index as the global
# row anchor so reports are precise even with out-of-order worker completion.
# Run: bundle exec ruby examples/parallel/progress_reporting/example.rb

require 'smarter_csv'
require 'tempfile'

SAMPLE_CSV = <<~CSV
  id,name,country
  #{(1..40).map { |i| "#{i},Person#{i},#{%w[US UK DE FR].sample}" }.join("\n")}
CSV

# Stand-in for a metrics sink. Production:
#   StatsD.gauge("csv_import.rows_processed", row_count, tags: ["batch_id:#{batch_id}"])
#   Prometheus::Client.registry.get(:csv_import_rows).increment(by: rows_in_this_slice)
#   ImportProgress.find_by(batch_id: batch_id).update!(rows_processed: ...)
class ProgressSink
  TOTAL_ROWS_EXPECTED = 40

  def self.report(batch_id:, slice_row_offset:, slice_rows_done:, slice_rows_total:)
    global_progress = slice_row_offset + slice_rows_done
    pct = (global_progress * 100.0 / TOTAL_ROWS_EXPECTED).round(1)
    puts "  [batch=#{batch_id}] slice@#{slice_row_offset}: #{slice_rows_done}/#{slice_rows_total} local; global #{global_progress}/#{TOTAL_ROWS_EXPECTED} (#{pct}%)"
  end
end

Tempfile.create(['progress_demo', '.csv']) do |f|
  f.write(SAMPLE_CSV)
  f.flush

  batch_id = "import-#{Time.now.to_i}"
  slices = SmarterCSV.slice(f.path, slice_size: 10, chunk_size: 5)
  puts "Importing batch_id=#{batch_id} with #{slices.size} slices."
  puts ""

  slices.each do |slice|
    # In a real worker, this batch yield is where you'd do the work + call ProgressSink.report
    rows_done = 0
    slice_total = slice[:to_byte] - slice[:from_byte] # not row count, but proxy; usually you'd track yields
    SmarterCSV.process_slice(slice) do |batch|
      rows_done += batch.size
      ProgressSink.report(
        batch_id:         batch_id,
        slice_row_offset: slice[:row_offset],
        slice_rows_done:  rows_done,
        slice_rows_total: 10,  # demo: slice_size; production: read from slicer metadata
      )
    end
  end

  puts ""
  puts "Import complete. ProgressSink saw #{slices.size * 2} reports (#{slices.size} slices × 2 chunks per slice)."
end
