# frozen_string_literal: true

require "core_ext/hash"

require "smarter_csv/version"
require "smarter_csv/smarter_csv"

if RUBY_ENGINE == 'ruby'
  path = `find tmp -name smarter_csv`.chomp
  if path.empty?
    puts "\n\nCOULD NOT DETERMINE PATH\n\n"
  else

    object_path = "#{path}/#{RUBY_VERSION}/smarter_csv"
    require_relative "../#{object_path}"

  end

  require 'smarter_csv/smarter_csv'

elsif RUBY_ENGINE == 'truffleruby'
  puts "\n\n truffleruby case in the load path | RUBY_ENGINE: #{RUBY_ENGINE} , #{RUBY_VERSION}\n\n"
  # this might not work - if you encounter problems, please contribute and create a PR
  # require 'truffleruby/smarter_csv'
  require 'smarter_csv/smarter_csv'

else
  puts <<-BLOCK_COMMENT

    -------------------------------------------------------------------------
      RUBY_ENGINE: #{RUBY_ENGINE} , #{RUBY_VERSION}

      Acceleration via C-Extension is currently not supported for #{RUBY_ENGINE}

      Please contribute and create a pull request if you need this
    -------------------------------------------------------------------------

  BLOCK_COMMENT
end
