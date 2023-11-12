# frozen_string_literal: true

require "bundler/gem_tasks"
require 'rspec/core/rake_task'

# # temp fix for NoMethodError: undefined method `last_comment'
# # remove when fixed in Rake 11.x and higher
# module TempFixForRakeLastComment
#   def last_comment
#     last_description
#   end
# end
# Rake::Application.send :include, TempFixForRakeLastComment
# ### end of tempfix

RSpec::Core::RakeTask.new(:spec)

require "rubocop/rake_task"

RuboCop::RakeTask.new

require "rake/extensiontask"

if RUBY_ENGINE == 'jruby'

  task default: %i[spec]

else
  task build: :compile

  Rake::ExtensionTask.new("smarter_csv") do |ext|
    ext.lib_dir = "lib/smarter_csv"
    ext.ext_dir = "ext/smarter_csv"
    ext.source_pattern = "*.{c,h}"
  end

  # task default: %i[clobber compile spec rubocop]
  task default: %i[clobber compile spec]
end

desc 'Run spec with coverage'
task :coverage do
  ENV['COVERAGE'] = 'true'
  Rake::Task['spec'].execute
  `open coverage/index.html`
end
