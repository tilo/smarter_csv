# frozen_string_literal: true

require "core_ext/hash"

require "smarter_csv/version"
require "smarter_csv/options_processing"

# require "smarter_csv/smarter_csv"



require 'smarter_csv.bundle' if `uname -s`.chomp == 'Darwin'

require_relative 'smarter_csv/smarter_csv'


# require_relative "smarter_csv/smarter_csv" unless ENV['CI'] # does not compile/link in CI?
# require 'smarter_csv.bundle' unless ENV['CI'] # local testing

# if RUBY_ENGINE == 'ruby'
#   path = `find tmp -name smarter_csv`.chomp
#   if path.empty?
#     # :nocov:
#     puts "\n\nCOULD NOT DETERMINE PATH\n\n"
#     require_relative "smarter_csv/smarter_csv"
#     # :nocov:
#   else

#     object_path = "#{path}/#{RUBY_VERSION}/smarter_csv"
#     require_relative "../#{object_path}"

#   end

#   require 'smarter_csv/smarter_csv'
# # :nocov:
# elsif RUBY_ENGINE == 'truffleruby'
#   puts "\n\n truffleruby case in the load path | RUBY_ENGINE: #{RUBY_ENGINE} , #{RUBY_VERSION}\n\n"
#   # this might not work - if you encounter problems, please contribute and create a PR
#   # require 'truffleruby/smarter_csv'
#   require 'smarter_csv/smarter_csv'

# else
#   puts <<-BLOCK_COMMENT

#     -------------------------------------------------------------------------
#       RUBY_ENGINE: #{RUBY_ENGINE} , #{RUBY_VERSION}

#       Acceleration via C-Extension is currently not supported for #{RUBY_ENGINE}

#       Please contribute and create a pull request if you need this
#     -------------------------------------------------------------------------

#   BLOCK_COMMENT
# end
# # :nocov:
