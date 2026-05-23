#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Sidekiq fan-in pattern: ImportSliceJob workers persist outputs to a shared store with an atomic
# counter; the last worker to finish triggers an AggregateResultsJob that builds the unified
# headers/warnings/errors result.
# Run: gem install sidekiq activesupport && bundle exec ruby examples/parallel/sidekiq_aggregator/example.rb
#
# Uses Sidekiq::Testing.inline! + an in-memory Hash as the shared store (instead of Redis) so it
# runs standalone. Production: replace SHARED_STORE with Redis hashes and SHARED_COUNTER with
# Redis DECR.

require 'smarter_csv'
require 'sidekiq'
require 'sidekiq/testing'
require 'active_support/core_ext/hash/keys'
require 'tempfile'

Sidekiq::Testing.inline!
Sidekiq.strict_args!(false)

class ImportSliceJob
  include Sidekiq::Job

  # Production: Redis hashes + Redis DECR atomic counter. Demo: simple Ruby objects.
  # Shared between ImportSliceJob (workers append to shared_store, decrement remaining_counter)
  # and AggregateResultsJob (reads shared_store after the counter hits zero).
  class << self
    attr_accessor :shared_store, :remaining_counter
  end
  self.shared_store      = Hash.new { |h, k| h[k] = [] } # batch_id → [{row_offset:, rows:, headers:, ...}, ...]
  self.remaining_counter = {}                            # batch_id → integer remaining

  def perform(slice_data, batch_id)
    slice = slice_data.deep_symbolize_keys
    slice[:headers] = slice[:headers].map(&:to_sym)
    slice[:options][:user_provided_headers] = slice[:options][:user_provided_headers].map(&:to_sym)
    %i[quote_escaping quote_boundary].each do |opt|
      slice[:options][opt] = slice[:options][opt].to_sym if slice[:options][opt].is_a?(String)
    end

    reader = SmarterCSV::Reader.new(slice[:input], slice[:options])
    rows   = reader.process_slice(slice)

    self.class.shared_store[batch_id] << {
      row_offset: slice[:row_offset],
      rows:       rows,
      headers:    reader.headers,
      warnings:   reader.warnings,
      errors:     reader.errors,
    }

    remaining = (self.class.remaining_counter[batch_id] -= 1)
    AggregateResultsJob.perform_async(batch_id) if remaining.zero?
  end
end

class AggregateResultsJob
  include Sidekiq::Job

  # Final per-batch aggregated record (headers union, warnings dedup, errors concat).
  class << self
    attr_accessor :aggregated
  end
  self.aggregated = {} # batch_id → { headers:, warnings:, errors:, row_count: }

  def perform(batch_id)
    results      = ImportSliceJob.shared_store[batch_id].sort_by { |r| r[:row_offset] }
    canonical    = results.first[:headers]                 # all slices carry the same canonical
    all_observed = results.flat_map { |r| r[:headers] }.uniq
    synthetics   = (all_observed - canonical).sort_by { |k| k.to_s[/\d+\z/].to_i }
    full_headers = canonical + synthetics

    all_warnings = results.flat_map { |r| r[:warnings] }
                          .group_by { |w| [w[:type], w[:code]] }
                          .map { |_, ws| ws.first.merge(count: ws.sum { |w| w[:count] }) }

    all_errors = {
      bad_row_count: results.sum { |r| r[:errors][:bad_row_count] || 0 },
      bad_rows:      results.flat_map { |r| r[:errors][:bad_rows] || [] },
    }

    self.class.aggregated[batch_id] = {
      headers:   full_headers,
      warnings:  all_warnings,
      errors:    all_errors,
      row_count: results.sum { |r| r[:rows].size },
    }
  end
end

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

Tempfile.create(['sidekiq_aggregator_demo', '.csv']) do |f|
  f.write(SAMPLE_CSV)
  f.flush

  batch_id = "demo-#{Time.now.to_i}"
  slices = SmarterCSV.slice(f.path, slice_size: 4)
  ImportSliceJob.remaining_counter[batch_id] = slices.size

  puts "Enqueuing #{slices.size} slice jobs (batch_id=#{batch_id}); AggregateResultsJob will fire when remaining hits 0..."
  slices.each { |s| ImportSliceJob.perform_async(s, batch_id) }

  puts ""
  puts "Aggregated result for batch_id=#{batch_id}:"
  result = AggregateResultsJob.aggregated[batch_id]
  puts "  total rows:    #{result[:row_count]}"
  puts "  full headers:  #{result[:headers].inspect}"
  puts "  warnings:      #{result[:warnings].size} unique"
  puts "  bad rows:      #{result[:errors][:bad_row_count]}"
end
