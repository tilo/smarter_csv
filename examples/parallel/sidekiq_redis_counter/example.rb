#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Sidekiq + Redis hash + atomic DECR counter for per-worker aggregation. Workers HSET their
# outputs to a Redis hash keyed by batch_id; an atomic DECR counter tracks remaining slices; the
# last worker to finish triggers the aggregator.
# Run: gem install sidekiq activesupport && bundle exec ruby examples/parallel/sidekiq_redis_counter/example.rb
#
# Demo uses Ruby Hashes as Redis stand-ins so it runs without infrastructure. Production: replace
# the stand-ins with Sidekiq.redis { |c| c.hset/c.decr/etc }.

require 'smarter_csv'
require 'sidekiq'
require 'sidekiq/testing'
require 'active_support/core_ext/hash/keys'
require 'json'
require 'tempfile'

Sidekiq::Testing.inline!
Sidekiq.strict_args!(false)

class ImportSliceJob
  include Sidekiq::Job

  # In production these are Redis operations:
  #   ImportSliceJob.hset[key][field] = value   → c.hset(key, field, value)
  #   ImportSliceJob.decr[key]        -= 1       → c.decr(key)
  # Demo uses Ruby objects on a single thread so the same atomicity guarantees hold by accident.
  class << self
    attr_accessor :hset, :decr
  end
  self.hset = Hash.new { |h, k| h[k] = {} }
  self.decr = {}

  def perform(slice_data, batch_id)
    slice = slice_data.deep_symbolize_keys
    slice[:headers] = slice[:headers].map(&:to_sym)
    slice[:options][:user_provided_headers] = slice[:options][:user_provided_headers].map(&:to_sym)
    %i[quote_escaping quote_boundary].each do |opt|
      slice[:options][opt] = slice[:options][opt].to_sym if slice[:options][opt].is_a?(String)
    end

    reader = SmarterCSV::Reader.new(slice[:input], slice[:options])
    rows   = reader.process_slice(slice)

    # Worker output → Redis hash, keyed by row_offset (field) inside batch_id (key)
    self.class.hset["import:#{batch_id}:results"][slice[:row_offset]] = JSON.dump(
      rows:     rows.map { |row| row.transform_keys(&:to_s) },
      headers:  reader.headers.map(&:to_s),
      warnings: reader.warnings,
      errors:   reader.errors,
    )

    # Atomic decrement; the worker that sees zero is the "last" one and triggers the aggregator
    remaining = (self.class.decr[batch_id] -= 1)
    AggregateResultsJob.perform_async(batch_id) if remaining.zero?
  end
end

class AggregateResultsJob
  include Sidekiq::Job

  def perform(batch_id)
    results = ImportSliceJob.hset["import:#{batch_id}:results"].map { |row_offset, payload|
      JSON.parse(payload, symbolize_names: true).merge(row_offset: row_offset.to_i)
    }.sort_by { |r| r[:row_offset] }

    canonical    = results.first[:headers].map(&:to_sym)
    all_observed = results.flat_map { |r| r[:headers] }.map(&:to_sym).uniq
    synthetics   = (all_observed - canonical).sort_by { |k| k.to_s[/\d+\z/].to_i }
    full_headers = canonical + synthetics

    puts ""
    puts "Aggregated by AggregateResultsJob for batch_id=#{batch_id}:"
    puts "  slices processed:   #{results.size}"
    puts "  total rows:         #{results.sum { |r| r[:rows].size }}"
    puts "  full headers:       #{full_headers.inspect}"
    puts "  warnings (total):   #{results.sum { |r| r[:warnings].size }}"
    puts "  bad rows (total):   #{results.sum { |r| r[:errors][:bad_row_count] || 0 }}"

    # Cleanup
    ImportSliceJob.hset.delete("import:#{batch_id}:results")
    ImportSliceJob.decr.delete(batch_id)
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

Tempfile.create(['sidekiq_redis_counter_demo', '.csv']) do |f|
  f.write(SAMPLE_CSV)
  f.flush

  batch_id = "demo-#{Time.now.to_i}"
  slices = SmarterCSV.slice(f.path, slice_size: 4)
  ImportSliceJob.decr[batch_id] = slices.size

  puts "Producer sets remaining=#{slices.size} in Redis; enqueuing slice jobs."
  puts "Each worker HSETs its result and atomically DECRs the counter; the worker that hits zero fires the aggregator."
  slices.each { |s| ImportSliceJob.perform_async(s, batch_id) }
end
