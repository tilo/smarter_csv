#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Bare-metal parallel processing via Process.fork + Process.wait — no gems, no framework.
# Educational: shows what the `parallel` gem does under the hood. Not recommended for
# production (use Parallel.each or Sidekiq instead — they handle the edge cases).
# Run: bundle exec ruby examples/parallel/manual_fork/example.rb

require 'smarter_csv'
require 'tempfile'

abort 'fork requires POSIX (not supported on Windows).' if Gem.win_platform?

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

Tempfile.create(['manual_fork_demo', '.csv']) do |f|
  f.write(SAMPLE_CSV)
  f.flush

  slices = SmarterCSV.slice(f.path, slice_size: 4)
  puts "Forking #{slices.size} child processes (one per slice)..."
  puts ""

  # Each child writes its parsed rows to its own tempfile; parent reads them after.
  # This is one IPC pattern; alternatives include pipes (more code) or Marshaling through stdout.
  per_child_tempfiles = slices.map { |slice|
    Tempfile.create(['fork_child_out', '.txt']) { |t| t.path }.tap { |p| File.delete(p) rescue nil }
  }

  child_pids = slices.map.with_index do |slice, i|
    out_path = "#{Dir.tmpdir}/fork_child_#{Process.pid}_#{i}.txt"

    pid = Process.fork do
      # Inside the child — separate Ruby process with its own GVL
      rows = SmarterCSV.process_slice(slice)
      File.open(out_path, 'w') do |out|
        out.puts "child pid=#{Process.pid}"
        out.puts "slice row_offset=#{slice[:row_offset]}"
        out.puts "rows processed: #{rows.size}"
        rows.each_with_index { |row, j| out.puts "  global_row #{slice[:row_offset] + j}: #{row.inspect}" }
      end
      exit!(0)   # exit! avoids running parent's at_exit handlers
    end

    per_child_tempfiles[i] = out_path
    pid
  end

  # Parent waits for each child
  child_pids.each_with_index do |pid, i|
    _, status = Process.wait2(pid)
    puts "Child pid=#{pid} (slice #{i}) exited with status=#{status.exitstatus}"
  end

  puts ""
  puts "=== Output from each child's tempfile ==="
  per_child_tempfiles.each do |path|
    puts "--- #{path} ---"
    puts File.read(path)
    File.delete(path)
  end
end
