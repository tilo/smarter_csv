# frozen_string_literal: true

require 'spec_helper'

# End-to-end demo: in-process serial slice processing.
#
# The simplest deployment pattern from docs/parallel_slicing.md — loop over slices in one
# Ruby process, no parallelism. Useful for rake tasks, CLI imports, environments without Sidekiq,
# or anywhere you want the streaming + batching of slice mode without orchestrating workers.
#
# Uses spec/fixtures/extra_columns_for_slicing.csv (12 rows, mixed widths) — different slices
# discover different synthetic :column_N columns, so the headers-aggregation pattern is
# non-trivial.

RSpec.describe 'slice mode — in-process serial loop' do
  let(:fixture) { 'spec/fixtures/extra_columns_for_slicing.csv' }
  let(:slice_size) { 4 } # 12 rows → 3 slices of 4
  let(:slices) { SmarterCSV.slice(fixture, slice_size: slice_size) }
  let(:whole)  { SmarterCSV.process(fixture) }
  let(:whole_reader_headers) do
    r = SmarterCSV::Reader.new(fixture, {})
    r.process
    r.headers
  end

  # Canonical headers-union pattern from docs/parallel_slicing.md.
  def union_headers(per_worker_headers, canonical:)
    all_observed = per_worker_headers.flatten.uniq
    synthetics   = (all_observed - canonical).sort_by { |k| k.to_s[/\d+\z/].to_i }
    canonical + synthetics
  end

  it 'concatenated per-slice rows match whole-file SmarterCSV.process' do
    combined = slices.flat_map { |s| SmarterCSV.process_slice(s) }
    expect(combined).to eq(whole)
  end

  it 'union of per-worker reader.headers matches whole-file reader.headers' do
    per_worker = slices.map do |s|
      r = SmarterCSV::Reader.new(s[:input], s[:options])
      r.process_slice(s)
      r.headers
    end

    # Sanity: the per-slice views should DIFFER (slice 0 doesn't see :column_7/:column_8) —
    # otherwise the aggregation pattern would be trivial and the fixture isn't doing its job.
    expect(per_worker.map(&:size).uniq.size).to be > 1

    expect(union_headers(per_worker, canonical: slices.first[:headers])).to eq(whole_reader_headers)
  end

  it 'a reused Reader accumulates @result across slices into the whole-file rows' do
    reader = SmarterCSV::Reader.new(slices.first[:input], slices.first[:options])
    slices.each { |s| reader.process_slice(s) }
    expect(reader.result).to eq(whole)
  end
end
