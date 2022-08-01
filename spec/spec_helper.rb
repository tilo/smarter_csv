# frozen_string_literal: true

require 'rubygems'
require 'bundler/setup'
require 'pry'

Fixnum = Integer unless defined?(Fixnum) # HACK: to allow Ruby 3.2 without having to rewrite the tests

require 'simplecov'
SimpleCov.start do
  add_filter '/spec/'
  add_filter "/pkg/"
end

if ENV['CI'] == 'true' || ENV['CODECOV_TOKEN']
  require 'codecov'
  SimpleCov.formatter = SimpleCov::Formatter::Codecov
end

Bundler.require(:default)
require 'smarter_csv'

# $LOAD_PATH.unshift File.expand_path('../ext/smarter_cvs', __FILE__)

RSpec.configure do |config|
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  # config.disable_monkey_patching!

  config.filter_run focus: true
  config.run_all_when_everything_filtered = true
end
