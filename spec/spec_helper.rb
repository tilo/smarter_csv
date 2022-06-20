require 'rubygems'
require 'bundler/setup'
require 'pry'

require 'simplecov'
SimpleCov.start do
  add_filter "/spec/"
end

if ENV['CI'] == 'true' || ENV['CODECOV_TOKEN']
  require 'codecov'
  SimpleCov.formatter = SimpleCov::Formatter::Codecov
end

Bundler.require(:default)

$LOAD_PATH.unshift File.expand_path('../ext', __FILE__)

require 'smarter_csv'

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.treat_symbols_as_metadata_keys_with_true_values = true
  config.filter_run :focus => true
  config.run_all_when_everything_filtered = true
end
