# frozen_string_literal: true

require "core_ext/hash"

require "smarter_csv/version"
require "smarter_csv/options_processing"

case RUBY_ENGINE
when 'ruby'
  begin
    if `uname -s`.chomp == 'Darwin'
      require 'smarter_csv/smarter_csv.bundle'
    else
      require_relative "smarter_csv/smarter_csv"
    end
  rescue Exception
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
require "smarter_csv/smarter_csv"
