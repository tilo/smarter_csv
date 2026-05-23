#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Sidekiq worker pattern for slice-mode processing.
# Run: gem install sidekiq activesupport && bundle exec ruby examples/parallel/sidekiq/example.rb
#
# Uses Sidekiq::Testing.inline! so no Redis is needed. Production deployment runs against real
# Redis + real Sidekiq workers — the worker code below is identical either way.

require 'smarter_csv'
require 'sidekiq'
require 'sidekiq/testing'
require 'active_support/core_ext/hash/keys'
require 'tempfile'

Sidekiq::Testing.inline!
# Sidekiq 8 rejects non-JSON-native job args by default. Slice hashes have symbol keys and arrays
# of symbols — disable strict_args so they pass through perform_async unchanged. Sidekiq still
# JSON-roundtrips them on the wire; the worker symbolizes back.
Sidekiq.strict_args!(false)

class ImportSliceJob
  include Sidekiq::Job

  # Stand-in for a DB table or Redis hash — what production deployments actually persist to.
  class << self
    attr_accessor :results
  end
  self.results = []

  def perform(slice_data)
    # Sidekiq lossily JSON-roundtrips args, so symbol keys arrive as strings. deep_symbolize_keys
    # recovers the Hash KEYS. Array elements (slice[:headers] = [:a, :b, ...]) and a few
    # symbol-VALUED options (quote_escaping, quote_boundary, on_bad_row, etc.) need targeted
    # .to_sym since deep_symbolize_keys only touches keys.
    slice = slice_data.deep_symbolize_keys
    slice[:headers] = slice[:headers].map(&:to_sym)
    slice[:options][:user_provided_headers] = slice[:options][:user_provided_headers].map(&:to_sym)
    %i[quote_escaping quote_boundary].each do |opt|
      slice[:options][opt] = slice[:options][opt].to_sym if slice[:options][opt].is_a?(String)
    end

    reader = SmarterCSV::Reader.new(slice[:input], slice[:options])
    rows   = reader.process_slice(slice)

    self.class.results << {
      pid:        Process.pid,
      row_offset: slice[:row_offset],
      rows:       rows,
      headers:    reader.headers,
      warnings:   reader.warnings,
      errors:     reader.errors,
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

Tempfile.create(['sidekiq_demo', '.csv']) do |f|
  f.write(SAMPLE_CSV)
  f.flush

  slices = SmarterCSV.slice(f.path, slice_size: 4)
  puts "Enqueuing #{slices.size} slice jobs to Sidekiq (inline mode)..."
  slices.each { |s| ImportSliceJob.perform_async(s) }

  puts ""
  puts "All workers complete. Shared store has #{ImportSliceJob.results.size} entries:"
  ImportSliceJob.results.sort_by { |r| r[:row_offset] }.each do |r|
    puts "  worker pid=#{r[:pid]} processed slice row_offset=#{r[:row_offset]} (#{r[:rows].size} rows; headers=#{r[:headers].inspect})"
  end
end
