#!/usr/bin/env rake
require "bundler/gem_tasks"
require 'rubygems'
require 'rake'
require 'rspec/core/rake_task'


require "rubygems/package_task"
### require 'rake/clean'
### CLEAN = FileList['ext/smarter_csv/smarter_csv.o'].exclude('*.c') # C A R E F U L !!!

require 'rake/extensiontask'
Rake::ExtensionTask.new('smarter_csv')

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

task :clean do
  cd "ext/smarter_csv"
  sh "rm -f Makefile"
  sh "rm -f smarter_csv.o"
  sh "rm -f smarter_csv.bundle"
  cd "../.."
end

task :create_makefile do
  cd "ext/smarter_csv"
  sh "ruby extconf.rb"
  cd "../.."
end

task :compile do
  cd "ext/smarter_csv"
  sh "ruby extconf.rb"
  sh "make"
  cd "../.."
end

task default: [:clean, :create_makefile, :compile, :spec]


# SMARTER_CSV_SPEC = Bundler.load_gemspec("smarter_csv.gemspec")
# exttask = Rake::ExtensionTask.new('smarter_csv', SMARTER_CSV_SPEC) do |ext|
#   ext.cross_compile = true
#   ext.cross_platform = %w[x86-mingw32 x64-mingw32 x86-linux x86_64-linux]
# end
