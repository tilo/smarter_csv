#!/usr/bin/env ruby
# frozen_string_literal: true
#
# GoodJob / Solid Queue worker pattern — same code shape as Sidekiq, different queue framework.
# Both are ActiveJob-based and use a Postgres-backed queue (no Redis required).
#
# Run: this example is a SKETCH. To actually run it you need:
#   - A Rails app with ActiveJob + GoodJob (or Solid Queue) installed and configured
#   - A Postgres DB the queue can write to
#   - Rails console / runner to enqueue the job
#
# Reading the code shows the production pattern. The "worker code" inside #perform is identical
# regardless of which queue backend you pick — that's the whole point of ActiveJob.

require 'smarter_csv'
# In a real Rails app you'd require Rails environment instead — that loads ActiveJob, GoodJob,
# ActiveRecord, etc. The below is the worker class definition; #perform runs identically under
# any ActiveJob backend.

# === GoodJob version ===
#
# class ImportSliceJob < ApplicationJob
#   queue_as :imports
#   retry_on StandardError, attempts: 5, wait: :polynomially_longer
#
#   def perform(slice_data, batch_id)
#     slice = slice_data.deep_symbolize_keys
#     slice[:headers] = slice[:headers].map(&:to_sym)
#     slice[:options][:user_provided_headers] = slice[:options][:user_provided_headers].map(&:to_sym)
#     %i[quote_escaping quote_boundary].each do |opt|
#       slice[:options][opt] = slice[:options][opt].to_sym if slice[:options][opt].is_a?(String)
#     end
#
#     reader = SmarterCSV::Reader.new(slice[:input], slice[:options])
#     reader.process_slice(slice) do |batch|
#       Model.upsert_all(batch, unique_by: :external_id)
#     end
#
#     SliceResult.create!(
#       batch_id:   batch_id,
#       row_offset: slice[:row_offset],
#       headers:    reader.headers,
#       warnings:   reader.warnings,
#       errors:     reader.errors,
#     )
#   end
# end

# === Solid Queue version (Rails 8 default) ===
#
# Identical to GoodJob version — both use ActiveJob.
#
# class ImportSliceJob < ApplicationJob
#   queue_as :imports
#   # Solid Queue uses ActiveJob retry semantics same as GoodJob
#   def perform(slice_data, batch_id)
#     # ... same body as GoodJob ...
#   end
# end

# === Producer (any of GoodJob / Solid Queue / Sidekiq — identical) ===
#
# class EnqueueImportJob < ApplicationJob
#   def perform(path)
#     batch_id = SecureRandom.uuid
#     SmarterCSV.slice(path, slice_size: 50_000, chunk_size: 500).each do |slice|
#       ImportSliceJob.perform_later(slice, batch_id)
#     end
#   end
# end

puts "GoodJob / Solid Queue example — code shape sketch only."
puts ""
puts "The worker code in #perform is identical regardless of queue framework:"
puts "  - Sidekiq:      include Sidekiq::Job"
puts "  - GoodJob:      class < ApplicationJob"
puts "  - Solid Queue:  class < ApplicationJob (same as GoodJob)"
puts "  - Resque:       class with @queue = :imports + self.perform(args)"
puts ""
puts "All of them use the same:"
puts "  1. deep_symbolize_keys on the slice data"
puts "  2. .map(&:to_sym) for headers / user_provided_headers"
puts "  3. .to_sym for symbol-valued options (quote_escaping, quote_boundary)"
puts "  4. SmarterCSV.process_slice(slice) for the actual work"
puts "  5. Per-worker state persisted to shared store (DB table or Redis hash)"
puts ""
puts "See spec/features/sidekiq_slicing_spec.rb for the runnable Sidekiq version, or examine the"
puts "commented code in this file for the GoodJob / Solid Queue shape."

# To actually run a GoodJob example you'd:
#   rails generate good_job:install
#   rails db:migrate
#   bin/good_job start &
#   rails runner 'EnqueueImportJob.perform_later("path/to/your.csv")'
