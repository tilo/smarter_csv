require 'rubygems'
require 'bundler/setup'

Bundler.require(:default)

require 'smarter_csv'


RSpec.configure do |config|
  config.filter_run :focus => true
  config.run_all_when_everything_filtered = true
#  config.fixture_path = 'spec/fixtures'

#  config.mock_with :rr
#  config.before(:each) do
#    Project.delete_all
#    Category.delete_all
#  end
end

