# frozen_string_literal: true

require "smarter_csv/version"
require "smarter_csv/errors"

require "smarter_csv/file_io"
require "smarter_csv/options"
require "smarter_csv/auto_detection"
require 'smarter_csv/header_transformations'
require 'smarter_csv/header_validations'
require "smarter_csv/headers"
require "smarter_csv/hash_transformations"

require "smarter_csv/parser"
require "smarter_csv/writer"
require "smarter_csv/reader"

# load the C-extension:
case RUBY_ENGINE
when 'ruby'
  begin
    if `uname -s`.chomp == 'Darwin'
      #
      # Please report if you see cases where the rake-compiler is building x86_64 code on arm64 cpus:
      # https://github.com/rake-compiler/rake-compiler/issues/231
      #
      require 'smarter_csv/smarter_csv.bundle'
    else
      # :nocov:
      require_relative "smarter_csv/smarter_csv"
      # :nocov:
    end
  rescue Exception # rubocop:disable Lint/RescueException
    #  require_relative 'smarter_csv/smarter_csv'
  end
# :nocov:
# when 'truffleruby'
#   puts "\n\n truffleruby case in the load path | RUBY_ENGINE: #{RUBY_ENGINE} , #{RUBY_VERSION}\n\n"
#   # this might not work - if you encounter problems, please contribute and create a PR
#   # require 'truffleruby/smarter_csv'
else
  puts <<-BLOCK_COMMENT

    -------------------------------------------------------------------------
      RUBY_ENGINE: #{RUBY_ENGINE} , #{RUBY_VERSION}

      Acceleration via C-Extension is currently not supported for #{RUBY_ENGINE}

      Please contribute and create a pull request if you need this
    -------------------------------------------------------------------------

  BLOCK_COMMENT
end
# :nocov:

module SmarterCSV
  # For backwards compatibility:
  #
  # while `SmarterCSV.process` works for simple cases, you can't get access to the internal state any longer.
  # e.g. you need the instance of the Reader to access the original headers
  #
  # Please use this instead:
  #
  #   reader = SmarterCSV::Reader.new(input, options)
  #   reader.process # with or without block
  #
  def self.process(input, given_options = {}, &block)
    reader = Reader.new(input, given_options)
    reader.process(&block)
  end

  # Convenience method for parsing a CSV string directly.
  # Equivalent to SmarterCSV.process(StringIO.new(csv_string), options).
  #
  # Example:
  #   data = SmarterCSV.parse("name,age\nAlice,30\nBob,25")
  #   # => [{name: "Alice", age: 30}, {name: "Bob", age: 25}]
  #
  #   SmarterCSV.parse("name,age\nAlice,30") { |chunk| chunk.each { |h| puts h } }
  #
  def self.parse(csv_string, options = {}, &block)
    process(StringIO.new(csv_string), options, &block)
  end

  # Yields each successfully parsed row as a Hash (row-by-row, Enumerable-compatible).
  # Returns an Enumerator when called without a block.
  #
  # Examples:
  #   SmarterCSV.each("data.csv") { |hash| MyModel.upsert(hash) }
  #   SmarterCSV.each("data.csv").select { |h| h[:country] == "US" }
  #   SmarterCSV.each("data.csv").lazy.map { |h| h[:name] }.first(10)
  def self.each(input, options = {}, &block)
    reader = Reader.new(input, options)
    reader.each(&block)
  end

  # Yields each chunk as Array<Hash> plus its 0-based chunk index.
  # Requires chunk_size to be set in options (must be >= 1).
  # Returns an Enumerator when called without a block.
  #
  # Examples:
  #   SmarterCSV.each_chunk("data.csv", chunk_size: 500) { |chunk, i| Sidekiq.push_bulk(chunk) }
  #   SmarterCSV.each_chunk("data.csv", chunk_size: 100).with_index { |chunk, i| ... }
  def self.each_chunk(input, options = {}, &block)
    reader = Reader.new(input, options)
    reader.each_chunk(&block)
  end

  # Convenience method for generating CSV files or writing to any IO object.
  #
  # Accepts a file path (String) or any IO-compatible object (StringIO, open File handle, etc.).
  # The caller retains ownership of any IO object passed in — SmarterCSV will not close it.
  #
  # Examples:
  #
  #   # Write to a file by path (existing behaviour)
  #   SmarterCSV.generate('output.csv', options) do |csv|
  #     MyModel.find_in_batches(batch_size: 100) do |batch|
  #       batch.each { |record| csv << record.attributes }
  #     end
  #   end
  #
  #   # Write to a StringIO (e.g. for Rails streaming responses)
  #   io = StringIO.new
  #   SmarterCSV.generate(io) do |csv|
  #     records.each { |r| csv << r }
  #   end
  #   send_data io.string, type: 'text/csv'
  #
  #   # Write to an already-open file handle
  #   File.open('output.csv', 'w') do |f|
  #     SmarterCSV.generate(f) do |csv|
  #       records.each { |r| csv << r }
  #     end
  #   end
  #
  # rubocop:disable Lint/UnusedMethodArgument
  def self.generate(file_path_or_io, options = {}, &block)
    raise ArgumentError, "SmarterCSV.generate requires a block" unless block_given?

    writer = Writer.new(file_path_or_io, options)
    yield writer
  ensure
    writer&.finalize
  end
  # rubocop:enable Lint/UnusedMethodArgument
end
