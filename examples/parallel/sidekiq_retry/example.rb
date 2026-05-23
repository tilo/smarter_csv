#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Idempotent slice workers — survive Sidekiq retries cleanly via upsert_all semantics.
# Run: gem install sidekiq activesupport && bundle exec ruby examples/parallel/sidekiq_retry/example.rb
#
# Demonstrates: slice X raises on first attempt, gets retried, succeeds on second attempt — no
# double-insert, no lost rows. The upsert-on-unique-key pattern is what makes this safe.

require 'smarter_csv'
require 'sidekiq'
require 'sidekiq/testing'
require 'active_support/core_ext/hash/keys'
require 'tempfile'

Sidekiq::Testing.inline!
Sidekiq.strict_args!(false)

# Stand-in for a DB table with a uniqueness constraint on (a, b). upsert_all semantics: insert
# if the (a, b) pair is new, ignore if it already exists. Production: this is a Postgres table
# with a unique index on the natural key.
FAKE_DB = {}              # composite (a, b) → row
INSERT_COUNTS = Hash.new(0) # composite (a, b) → number of times we tried to insert (for verification)
RETRY_ATTEMPTS = Hash.new(0) # slice row_offset → number of perform attempts

class ImportSliceJob
  include Sidekiq::Job
  sidekiq_options retry: 5

  def perform(slice_data)
    slice = slice_data.deep_symbolize_keys
    slice[:headers] = slice[:headers].map(&:to_sym)
    slice[:options][:user_provided_headers] = slice[:options][:user_provided_headers].map(&:to_sym)
    %i[quote_escaping quote_boundary].each do |opt|
      slice[:options][opt] = slice[:options][opt].to_sym if slice[:options][opt].is_a?(String)
    end

    RETRY_ATTEMPTS[slice[:row_offset]] += 1
    attempt = RETRY_ATTEMPTS[slice[:row_offset]]

    SmarterCSV.process_slice(slice) do |batch|
      batch.each do |row|
        key = [row[:a], row[:b]]
        INSERT_COUNTS[key] += 1
        FAKE_DB[key] ||= row    # upsert: first writer wins; later writers are no-ops on the key
      end
    end

    # Deliberately fail the first attempt of slice row_offset=4 to demonstrate retry survival.
    # Production: this is a real failure — DB blip, deploy mid-job, network glitch, etc.
    if slice[:row_offset] == 4 && attempt == 1
      raise "Simulated transient failure on slice row_offset=4, attempt=#{attempt}"
    end
  end
end

SAMPLE_CSV = <<~CSV
  a,b,c,d
  1,2,3,4
  5,6,7,8
  9,10,11,12
  13,14,15,16
  17,18,19,20
  21,22,23,24
  25,26,27,28
  29,30,31,32
CSV

Tempfile.create(['sidekiq_retry_demo', '.csv']) do |f|
  f.write(SAMPLE_CSV)
  f.flush

  slices = SmarterCSV.slice(f.path, slice_size: 4)
  puts "Enqueuing #{slices.size} slices. Slice row_offset=4 will fail on first attempt and succeed on retry."
  puts ""

  slices.each do |slice|
    begin
      ImportSliceJob.perform_async(slice)
    rescue => e
      # In real Sidekiq this is automatic. Sidekiq::Testing.inline! re-raises, so we trigger the
      # retry manually here to demonstrate the recovery shape.
      puts "  Slice row_offset=#{slice[:row_offset]} failed: #{e.message}"
      puts "  Sidekiq would now retry it. Re-enqueueing manually..."
      ImportSliceJob.perform_async(slice)
    end
  end

  puts ""
  puts "Final state of FAKE_DB (#{FAKE_DB.size} unique rows):"
  FAKE_DB.each { |k, row| puts "  #{k} → #{row.inspect}" }

  puts ""
  puts "Insert attempts per (a, b) key (should be 1 for most, 2 for slice row_offset=4's rows):"
  INSERT_COUNTS.each { |k, count| puts "  #{k} → #{count} insert attempt(s)" }

  puts ""
  puts "Retries per slice (slice 4 should show 2 attempts):"
  RETRY_ATTEMPTS.each { |row_offset, attempts| puts "  slice row_offset=#{row_offset} → #{attempts} attempt(s)" }

  duplicates = INSERT_COUNTS.values.count { |c| c > 1 }
  puts ""
  puts "Idempotency check: #{duplicates} rows were inserted >1 time."
  puts "  Without upsert semantics, those would have been duplicates → broken import."
  puts "  With upsert (FAKE_DB[key] ||= row), the second write is a no-op → safe retry."
end
