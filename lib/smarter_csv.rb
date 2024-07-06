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

  # Convenience method for generating CSV files:
  #
  # SmarterCSV.generate(filename, options) do |csv_writer|
  #   MyModel.find_in_batches(batch_size: 100) do |batch|
  #    batch.pluck(:name, :description, :instructor).each do |record|
  #       csv_writer << record
  #     end
  #   end
  # end
  #
  # rubocop:disable Lint/UnusedMethodArgument
  def self.generate(filename, options = {}, &block)
    raise unless block_given?

    writer = Writer.new(filename, options)
    yield writer
  ensure
    writer.finalize
  end
  # rubocop:enable Lint/UnusedMethodArgument
end
