#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Map-reduce over slices: each worker computes partial aggregates (sum, count, distinct sets)
# over its slice; the parent reduces them into a final analytics record.
# Run: gem install parallel && bundle exec ruby examples/parallel/map_reduce_aggregation/example.rb

require 'smarter_csv'
require 'parallel'
require 'set'
require 'tempfile'

abort 'Parallel.map requires fork — POSIX only (not supported on Windows).' if Gem.win_platform?

SAMPLE_CSV = <<~CSV
  order_id,customer_id,country,amount,currency
  1001,42,US,150.00,USD
  1002,17,UK,89.50,GBP
  1003,42,US,75.25,USD
  1004,93,DE,220.00,EUR
  1005,17,UK,45.00,GBP
  1006,42,US,310.00,USD
  1007,55,FR,180.00,EUR
  1008,93,DE,95.75,EUR
  1009,17,UK,125.00,GBP
  1010,42,US,200.00,USD
  1011,55,FR,67.50,EUR
  1012,93,DE,140.00,EUR
CSV

Tempfile.create(['map_reduce_demo', '.csv']) do |f|
  f.write(SAMPLE_CSV)
  f.flush

  slices = SmarterCSV.slice(f.path, slice_size: 4)
  puts "Map-reduce: #{slices.size} slices, parallel map → single reduce."
  puts ""

  # MAP: each worker computes partial aggregates over its slice
  partials = Parallel.map(slices, in_processes: [slices.size, Parallel.processor_count].min) do |slice|
    rows = SmarterCSV.process_slice(slice)
    partial = {
      row_offset:        slice[:row_offset],
      worker_pid:        Process.pid,
      row_count:         rows.size,
      total_by_currency: Hash.new(0.0),
      orders_by_country: Hash.new(0),
      distinct_customers: Set.new,
      max_order_amount:  0.0,
    }
    rows.each do |row|
      partial[:total_by_currency][row[:currency]] += row[:amount].to_f
      partial[:orders_by_country][row[:country]] += 1
      partial[:distinct_customers] << row[:customer_id]
      partial[:max_order_amount] = [partial[:max_order_amount], row[:amount].to_f].max
    end
    partial
  end

  partials.each do |p|
    puts "  worker pid=#{p[:worker_pid]} row_offset=#{p[:row_offset]}: #{p[:row_count]} rows"
    puts "    by_currency: #{p[:total_by_currency].inspect}"
    puts "    distinct_customers: #{p[:distinct_customers].to_a.sort.inspect}"
  end

  # REDUCE: combine partials into the final aggregate
  total_rows         = partials.sum { |p| p[:row_count] }
  total_by_currency  = partials.each_with_object(Hash.new(0.0)) { |p, acc| p[:total_by_currency].each { |k, v| acc[k] += v } }
  orders_by_country  = partials.each_with_object(Hash.new(0)) { |p, acc| p[:orders_by_country].each { |k, v| acc[k] += v } }
  distinct_customers = partials.flat_map { |p| p[:distinct_customers].to_a }.uniq.sort
  max_order_amount   = partials.map { |p| p[:max_order_amount] }.max

  puts ""
  puts "REDUCED final result:"
  puts "  total rows:          #{total_rows}"
  puts "  total by currency:   #{total_by_currency.inspect}"
  puts "  orders by country:   #{orders_by_country.inspect}"
  puts "  distinct customers:  #{distinct_customers.inspect}"
  puts "  max order amount:    #{max_order_amount}"
end
