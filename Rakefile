#!/usr/bin/env rake
require 'rake'
require 'rspec/core/rake_task'
require "bundler/gem_tasks"
require 'rubygems'

task default: :spec
task test: :spec

desc "Run RSpec"
RSpec::Core::RakeTask.new do |t|
  # t.verbose = false
end

desc 'Run spec with coverage'
task :coverage do
  ENV['COVERAGE'] = 'true'
  Rake::Task['spec'].execute
  `open coverage/index.html`
end
