# frozen_string_literal: true

require 'spec_helper'
require 'parallel'
require 'json'

# End-to-end demo: in-process parallel slice processing via the `parallel` gem (fork-based).
#
# Pattern from docs/parallel_slicing.md — true CPU parallelism via forked child processes, each
# pulling work items from a queue managed by the parent. POSIX-only (`fork`-dependent); skipped
# on Windows.
#
# Two variants demonstrated:
#   - Parallel.map: workers return their parsed rows; parent Marshal-receives and flattens.
#     Easy to test because results come back automatically. The doc recommends .each over .map
#     for production "process and discard / write to DB" workflows (to avoid Marshaling rows
#     back), but .map is the right tool here for the test.
#   - Parallel.each + per-slice tempfiles: workers write rows to deterministic per-slice file
#     paths; parent reads them after Parallel.each completes. Demonstrates the "side-effect
#     workflow" shape — what a real importer doing DB writes inside each worker would look like.

RSpec.describe 'slice mode — in-process parallel via the parallel gem' do
  let(:fixture) { 'spec/fixtures/extra_columns_for_slicing.csv' }
  let(:slice_size) { 4 } # 12 rows → 3 slices of 4
  let(:slices) { SmarterCSV.slice(fixture, slice_size: slice_size) }
  let(:whole)  { SmarterCSV.process(fixture) }
  let(:whole_reader_headers) do
    r = SmarterCSV::Reader.new(fixture, {})
    r.process
    r.headers
  end

  def union_headers(per_worker_headers, canonical:)
    all_observed = per_worker_headers.flatten.uniq
    synthetics   = (all_observed - canonical).sort_by { |k| k.to_s[/\d+\z/].to_i }
    canonical + synthetics
  end

  before do
    skip 'Parallel.map / .each require fork (POSIX-only)' if Gem.win_platform?
  end

  it 'Parallel.map: forked workers preserve input order; flat results match whole-file rows' do
    results = Parallel.map(slices, in_processes: 2) do |s|
      SmarterCSV.process_slice(s)
    end

    expect(results.flatten).to eq(whole)
  end

  it 'Parallel.map: forked workers return per-slice headers; parent unions to whole-file headers' do
    per_worker = Parallel.map(slices, in_processes: 2) do |s|
      reader = SmarterCSV::Reader.new(s[:input], s[:options])
      reader.process_slice(s)
      reader.headers
    end

    expect(union_headers(per_worker, canonical: slices.first[:headers])).to eq(whole_reader_headers)
  end

  it 'Parallel.each + per-slice tempfiles: workers write side-effects; parent reads in slice order' do
    Dir.mktmpdir do |dir|
      Parallel.each(slices, in_processes: 2) do |s|
        out_path = File.join(dir, "slice_#{format('%010d', s[:row_offset])}.jsonl")
        File.open(out_path, 'w') do |f|
          SmarterCSV.process_slice(s) do |batch|
            batch.each { |row| f.puts JSON.generate(row) }
          end
        end
      end

      # Workers finish in arbitrary order — files are sorted by row_offset (encoded in the name).
      ordered_paths = Dir.glob(File.join(dir, 'slice_*.jsonl')).sort
      rows_from_disk = ordered_paths.flat_map do |p|
        File.readlines(p, chomp: true).map { |line| JSON.parse(line, symbolize_names: true) }
      end

      # Round-trip whole-file rows through JSON too so the comparison is apples-to-apples
      # (symbol keys preserved by symbolize_names: true; values preserve their JSON-native types).
      expected = JSON.parse(JSON.generate(whole), symbolize_names: true)
      expect(rows_from_disk).to eq(expected)
    end
  end
end
