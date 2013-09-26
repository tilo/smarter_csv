#!/usr/bin/env rake
require "bundler/gem_tasks"
require "rake/testtask"

Rake::TestTask.new do |t|
  t.test_files = FileList['spec/*_spec.rb']
end
task :default => :test
