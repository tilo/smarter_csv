require 'rubygems'
require 'bundler/setup'

Bundler.require(:default)

require 'smarter_csv'

SimpleCov.start do
  add_filter /spec/
end

RSpec.configure do |config|

  config.filter_run_when_matching :focus

  config.treat_symbols_as_metadata_keys_with_true_values = true

  config.run_all_when_everything_filtered = true
end
