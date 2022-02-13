#!/usr/bin/env rake
require "bundler/gem_tasks"
require 'rubygems'
require 'rake'
require 'rspec/core/rake_task'

task :default => :spec

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
