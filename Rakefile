# frozen_string_literal: true

require "bundler/gem_tasks"
require 'rspec/core/rake_task'

RSpec::Core::RakeTask.new(:spec)

require "rubocop/rake_task"

RuboCop::RakeTask.new

require "rake/extensiontask"

task build: :compile

Rake::ExtensionTask.new("smarter_csv") do |ext|
  ext.ext_dir = "ext/smarter_csv"
end

# task default: %i[clobber compile spec rubocop]
task default: %i[clobber compile spec]
