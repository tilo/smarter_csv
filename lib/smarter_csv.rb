if ENV['COVERAGE']
  require 'simplecov'
  SimpleCov.start do
    add_filter "/spec/"
    add_filter "/pkg/"
  end
end

require 'csv'
require "smarter_csv/version"
require "extensions/hash.rb"
require "smarter_csv/smarter_csv.rb"
