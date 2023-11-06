# frozen_string_literal: true

require "core_ext/hash"

require "smarter_csv/version"
require "smarter_csv/options_processing"

case RUBY_ENGINE
when 'ruby'
  path = `find tmp -name smarter_csv`.chomp

  begin
    object_path = "#{path}/#{RUBY_VERSION}/smarter_csv"
    require_relative "../#{object_path}"
  rescue Exception
    # :nocov:
    case `uname -s`.chomp
    when 'Darwin'
      require 'smarter_csv.bundle'
    else
      require_relative 'smarter_csv/smarter_csv'
    end
    # :nocov:
  end
# :nocov:
# elsif RUBY_ENGINE == 'truffleruby'
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
