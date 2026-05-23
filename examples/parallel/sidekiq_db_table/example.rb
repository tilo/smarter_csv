#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Sidekiq + DB table for per-worker state aggregation. Each slice worker INSERTs a row carrying
# its reader.headers / .warnings / .errors keyed by batch_id; the orchestrator queries by
# batch_id after all workers finish.
#
# Run: gem install sidekiq activesupport && bundle exec ruby examples/parallel/sidekiq_db_table/example.rb
#
# Production: SliceResult is an ActiveRecord model backed by a real DB. Demo: a Ruby Array stands
# in for the table so the example runs standalone.

require 'smarter_csv'
require 'sidekiq'
require 'sidekiq/testing'
require 'active_support/core_ext/hash/keys'
require 'tempfile'

Sidekiq::Testing.inline!
Sidekiq.strict_args!(false)

# Stand-in for an ActiveRecord model:
#   class SliceResult < ActiveRecord::Base
#     # columns: batch_id (string), row_offset (integer), headers/warnings/errors (jsonb)
#   end
# The Struct's class-level `records` collection stands in for the database table itself.
SliceResult = Struct.new(:batch_id, :row_offset, :rows, :headers, :warnings, :errors, keyword_init: true) do
  class << self
    attr_accessor :records

    def where(batch_id:)
      records.select { |r| r.batch_id == batch_id }
    end
  end
end
SliceResult.records = []

class ImportSliceJob
  include Sidekiq::Job

  def perform(slice_data, batch_id)
    slice = slice_data.deep_symbolize_keys
    slice[:headers] = slice[:headers].map(&:to_sym)
    slice[:options][:user_provided_headers] = slice[:options][:user_provided_headers].map(&:to_sym)
    %i[quote_escaping quote_boundary].each do |opt|
      slice[:options][opt] = slice[:options][opt].to_sym if slice[:options][opt].is_a?(String)
    end

    reader = SmarterCSV::Reader.new(slice[:input], slice[:options])
    rows   = reader.process_slice(slice)

    # Production: SliceResult.create!(batch_id: ..., headers: ..., ...) hits the DB.
    SliceResult.records << SliceResult.new(
      batch_id:   batch_id,
      row_offset: slice[:row_offset],
      rows:       rows,
      headers:    reader.headers,
      warnings:   reader.warnings,
      errors:     reader.errors,
    )
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

Tempfile.create(['sidekiq_db_table_demo', '.csv']) do |f|
  f.write(SAMPLE_CSV)
  f.flush

  batch_id = "demo-#{Time.now.to_i}"
  slices = SmarterCSV.slice(f.path, slice_size: 4)
  puts "Enqueuing #{slices.size} slice jobs for batch_id=#{batch_id}..."
  slices.each { |s| ImportSliceJob.perform_async(s, batch_id) }

  puts ""
  puts "Querying SliceResult table for batch_id=#{batch_id}:"
  results = SliceResult.where(batch_id: batch_id).sort_by(&:row_offset)
  results.each do |r|
    puts "  row_offset=#{r.row_offset}: #{r.rows.size} rows, headers=#{r.headers.size} (#{r.headers.last.inspect} is the widest synthetic)"
  end

  # Orchestrator-side aggregation
  canonical    = slices.first[:headers]
  all_observed = results.flat_map(&:headers).uniq
  synthetics   = (all_observed - canonical).sort_by { |k| k.to_s[/\d+\z/].to_i }
  full_headers = canonical + synthetics

  puts ""
  puts "Aggregated from DB table:"
  puts "  full headers: #{full_headers.inspect}"
  puts "  total rows:   #{results.sum { |r| r.rows.size }}"
end
