# frozen_string_literal: true

require "core_ext/hash"

require "smarter_csv/version"
require "smarter_csv/smarter_csv"

# require_relative "smarter_csv/smarter_csv" unless ENV['CI'] # does not compile/link in CI?
# require 'smarter_csv.bundle' unless ENV['CI'] # local testing

if RUBY_ENGINE == 'ruby'
  begin
    path = `find tmp -name smarter_csv`.chomp
    require_relative "../#{path}/#{RUBY_VERSION}/smarter_csv.bundle"

    rescue Exception => e

      puts "\n\n BAM BAM BAM - we're not on a Mac \n\n #{e.inspect}"

      # require 'smarter_csv/smarter_csv'
  end

  require 'smarter_csv/smarter_csv'

elsif RUBY_ENGINE == 'truffleruby' && (RUBY_ENGINE_VERSION.split('.').map(&:to_i) <=> [20, 1, 0]) >= 0
  require 'truffleruby/smarter_csv'
  require 'smarter_csv/smarter_csv'
else
  # Remove the smarter_csv gem dir from the load path, then reload the internal smarter_csv implementation
  $LOAD_PATH.delete(File.dirname(__FILE__))
  $LOAD_PATH.delete(File.join(File.dirname(__FILE__), 'smarter_csv'))
  unless $LOADED_FEATURES.nil?
    $LOADED_FEATURES.delete(__FILE__)
    $LOADED_FEATURES.delete('smarter_csv.rb')
  end
  require 'smarter_csv.rb'
end
