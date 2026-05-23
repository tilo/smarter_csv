# frozen_string_literal: true

require 'spec_helper'
require 'sidekiq'
require 'sidekiq/testing'
require 'active_support/core_ext/hash/keys' # for Hash#deep_symbolize_keys

# End-to-end demo: Sidekiq-based slice processing.
#
# Pattern from docs/parallel_slicing.md — workers run as Sidekiq jobs (separate processes in
# production), each handling one slice; an orchestrator collects per-worker outputs from a
# shared store after a "batch complete" signal.
#
# These specs use Sidekiq::Testing.inline! — perform_async runs the worker's #perform method
# synchronously in the test process. That gives us:
#   - The same Sidekiq::Job code shape production uses (perform_async, the job class)
#   - No Redis server required for the test run
#   - Deterministic, synchronous execution for assertions
#
# What inline mode does NOT simulate: in real Sidekiq, job args are JSON-serialized through
# Redis. Symbol keys arrive as strings on the worker side. Production code should normalize
# the slice's keys before handing it to SmarterCSV.process_slice — typically:
#     slice = JSON.parse(slice_hash.to_json, symbolize_names: true)
# In inline mode, args are passed through without serialization, so this normalization is a
# no-op here. The job below includes the normalization step regardless, so the code shape
# matches what users should ship.

Sidekiq::Testing.inline!

# Production-realism note. Sidekiq JSON-roundtrips job args on the wire (Redis-backed in
# production; Sidekiq::Testing.inline! mode replicates the same JSON roundtrip). On arrival
# the worker's slice Hash has STRING keys instead of symbols, and arrays-of-symbols
# (slice[:headers], slice[:options][:user_provided_headers]) have flattened to arrays of
# strings. Two steps recover the original shape:
#   - ActiveSupport's Hash#deep_symbolize_keys to recursively re-symbolize keys
#   - explicit .map(&:to_sym) on the headers arrays (whose elements are values inside Arrays,
#     not Hash keys — deep_symbolize_keys leaves them alone)
# Sidekiq.strict_args! is disabled so the producer can pass the symbol-laden slice through
# perform_async unchanged — without that, Sidekiq would reject the slice's symbol keys at
# enqueue time.
Sidekiq.strict_args!(false)

class ImportSliceJob
  include Sidekiq::Job

  # Stand-in "shared store" — represents the DB table / Redis hash described in
  # docs/parallel_slicing.md's "Aggregation, cross-process (Sidekiq)" section. Workers
  # append their per-slice output; the orchestrator reads it after all jobs complete.
  class << self
    attr_accessor :results
  end
  self.results = []

  def perform(slice_data)
    slice = slice_data.deep_symbolize_keys
    slice[:headers] = slice[:headers].map(&:to_sym)
    slice[:options][:user_provided_headers] = slice[:options][:user_provided_headers].map(&:to_sym)

    # Symbol-valued options that arrive as strings after JSON serialization.
    # Reader::Options validates these against an allow-list of symbols, so strings get rejected.
    # If your slice's options carry other symbol-valued keys (on_bad_row, verbose, missing_headers,
    # etc.), add them here.
    %i[quote_escaping quote_boundary].each do |opt|
      slice[:options][opt] = slice[:options][opt].to_sym if slice[:options][opt].is_a?(String)
    end

    reader = SmarterCSV::Reader.new(slice[:input], slice[:options])
    rows   = reader.process_slice(slice)

    self.class.results << {
      row_offset: slice[:row_offset],
      rows: rows,
      headers: reader.headers,
      warnings: reader.warnings,
      errors: reader.errors,
    }
  end
end

RSpec.describe 'slice mode — Sidekiq worker pattern (Sidekiq::Testing.inline!)' do
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

  before { ImportSliceJob.results.clear }

  it 'workers persist their outputs to the shared store; orchestrator concatenates rows in slice order' do
    slices.each { |s| ImportSliceJob.perform_async(s) }

    # Real Sidekiq workers complete in arbitrary order — sort by row_offset to recover slice
    # order. The synchronous inline! execution happens to be in order already, but the sort is
    # what production orchestrator code does.
    ordered = ImportSliceJob.results.sort_by { |r| r[:row_offset] }
    expect(ordered.flat_map { |r| r[:rows] }).to eq(whole)
  end

  it 'orchestrator unions per-worker headers from the shared store into whole-file headers' do
    slices.each { |s| ImportSliceJob.perform_async(s) }

    per_worker = ImportSliceJob.results.map { |r| r[:headers] }
    expect(union_headers(per_worker, canonical: slices.first[:headers])).to eq(whole_reader_headers)
  end

  it 'workers collect per-slice errors/warnings independently (no cross-worker contamination)' do
    slices.each { |s| ImportSliceJob.perform_async(s) }

    # This fixture is clean — no bad rows, no warnings — so every per-worker .errors / .warnings
    # should be empty. The assertion captures the contract that errors stay scoped per worker;
    # if a real anomaly appeared, only the slice that contained it would carry it.
    ImportSliceJob.results.each do |r|
      expect(r[:errors][:bad_row_count] || 0).to eq(0)
      expect(r[:warnings]).to be_empty
    end
  end
end
