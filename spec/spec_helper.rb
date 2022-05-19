require 'bundler/setup'
require 'rubygems'
require 'simplecov'

Bundler.require(:default)

SimpleCov.start

if ENV['CI'] == 'true' || ENV['CODECOV_TOKEN']
  require 'codecov'
  SimpleCov.formatter = SimpleCov::Formatter::Codecov
end

require 'smarter_csv'

RSpec.configure do |config|

  config.filter_run focus: true

  config.treat_symbols_as_metadata_keys_with_true_values = true

  config.run_all_when_everything_filtered = true
end
