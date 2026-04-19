# frozen_string_literal: true

require 'stringio'
require "smarter_csv/version"
require "smarter_csv/errors"

require "smarter_csv/file_io"
require "smarter_csv/reader_options"
require "smarter_csv/writer_options"
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
  # After calling any of the class-level methods, errors from the last run are available via:
  #
  #   SmarterCSV.errors  # => { bad_row_count: 2, bad_rows: [...] }
  #
  # This exposes the same reader.errors hash without requiring access to the Reader instance.
  # Errors are cleared at the start of each call and stored per-thread, so this is safe in
  # multi-threaded environments (Puma, Sidekiq). Note: only the most recent call's errors
  # are retained per thread.
  #
  def self.process(input, given_options = {}, &block)
    Thread.current[:current_thread_recent_errors] = {}
    reader = Reader.new(input, given_options)
    reader.process(&block)
  ensure
    # Preserve partial error state when processing raises mid-stream
    # (e.g. TooManyBadRows, or a user block raising). `reader` is nil if
    # Reader.new itself raised before the local was assigned.
    Thread.current[:current_thread_recent_errors] = reader.errors if reader
  end

  # Convenience method for parsing a CSV string directly.
  # Equivalent to SmarterCSV.process(StringIO.new(csv_string), options).
  # Errors from the run are available via SmarterCSV.errors after the call.
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
  # When called with a block, errors from the run are available via SmarterCSV.errors after the call.
  # When called without a block (Enumerator form), use SmarterCSV::Reader directly for error access.
  #
  # Examples:
  #   SmarterCSV.each("data.csv") { |hash| MyModel.upsert(hash) }
  #   SmarterCSV.each("data.csv").select { |h| h[:country] == "US" }
  #   SmarterCSV.each("data.csv").lazy.map { |h| h[:name] }.first(10)
  def self.each(input, options = {}, &block)
    Thread.current[:current_thread_recent_errors] = {}
    reader = Reader.new(input, options)
    reader.each(&block)
  ensure
    Thread.current[:current_thread_recent_errors] = reader.errors if reader
  end

  # Yields each chunk as Array<Hash> plus its 0-based chunk index.
  # Requires chunk_size to be set in options (must be >= 1).
  # Returns an Enumerator when called without a block.
  # When called with a block, errors from the run are available via SmarterCSV.errors after the call.
  # When called without a block (Enumerator form), use SmarterCSV::Reader directly for error access.
  #
  # Examples:
  #   SmarterCSV.each_chunk("data.csv", chunk_size: 500) { |chunk, i| Sidekiq.push_bulk(chunk) }
  #   SmarterCSV.each_chunk("data.csv", chunk_size: 100).with_index { |chunk, i| ... }
  def self.each_chunk(input, options = {}, &block)
    Thread.current[:current_thread_recent_errors] = {}
    reader = Reader.new(input, options)
    reader.each_chunk(&block)
  ensure
    Thread.current[:current_thread_recent_errors] = reader.errors if reader
  end

  # Returns the errors from the most recent call to .process, .parse, .each, or .each_chunk
  # on the current thread. Cleared at the start of each new call.
  #
  # Keys (when on_bad_row: :skip or :collect is used):
  #   :bad_row_count  — total number of bad rows encountered
  #   :bad_rows       — array of error records (only with on_bad_row: :collect)
  #
  # Example:
  #   SmarterCSV.process('data.csv', on_bad_row: :skip)
  #   puts SmarterCSV.errors[:bad_row_count]
  #
  def self.errors
    Thread.current[:current_thread_recent_errors] || {}
  end

  # Convenience method for generating CSV files, IO objects, or in-memory strings.
  #
  # When called WITHOUT a first argument, generates CSV in memory and returns it as a String.
  # When called WITH a file path (String/Pathname) or any IO-compatible object (StringIO,
  # open File handle, etc.), writes to that destination and returns nil.
  # The caller retains ownership of any IO object passed in — SmarterCSV will not close it.
  #
  # Examples:
  #
  #   # Return CSV as a String (no file argument)
  #   csv_string = SmarterCSV.generate(options) do |csv|
  #     records.each { |r| csv << r }
  #   end
  #
  #   # Write to a file by path
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
  def self.generate(file_path_or_io = nil, options = {}, &block)
    raise ArgumentError, "SmarterCSV.generate requires a block" unless block_given?

    # When called as generate(options_hash) { }, the hash lands in file_path_or_io
    if file_path_or_io.is_a?(Hash)
      options = file_path_or_io
      file_path_or_io = nil
    end

    if file_path_or_io.nil?
      # No destination given — write to an in-memory StringIO and return the result as a String.
      io = StringIO.new
      writer = Writer.new(io, options)
      begin
        yield writer
      ensure
        writer&.finalize # must finalize before reading io.string
      end
      io.string
    else
      writer = Writer.new(file_path_or_io, options)
      begin
        yield writer
      ensure
        writer&.finalize
      end
    end
  end
  # rubocop:enable Lint/UnusedMethodArgument
end
