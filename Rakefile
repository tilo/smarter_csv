#!/usr/bin/env rake
require "bundler/gem_tasks"
require "rake/testtask"

gemspec = Bundler::GemHelper.gemspec

Rake::TestTask.new do |spec|
  spec.libs << "spec"
  spec.test_files = gemspec.test_files
end
task :default => :test
