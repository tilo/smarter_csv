require 'rubygems'
require 'bundler/setup'
require 'pry'

require 'simplecov'
SimpleCov.start do
  add_filter "/spec/"
end

Bundler.require(:default)

$LOAD_PATH.unshift File.expand_path('../ext', __FILE__)

require 'smarter_csv'

RSpec.configure do |config|
  config.treat_symbols_as_metadata_keys_with_true_values = true
  config.filter_run :focus => true
  config.run_all_when_everything_filtered = true
end
