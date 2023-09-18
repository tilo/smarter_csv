# -*- encoding: utf-8 -*-
# frozen_string_literal: true

require File.expand_path('lib/smarter_csv/version', __dir__)

Gem::Specification.new do |gem|
  gem.name          = "smarter_csv"
  gem.version       = SmarterCSV::VERSION
  gem.authors       = ["Tilo Sloboda\n"]
  gem.email         = ["tilo.sloboda@gmail.com\n"]

  gem.summary       = 'Ruby Gem for smarter importing of CSV Files (and CSV-like files), with lots of optional features, e.g. chunked processing for huge CSV files'
  gem.description   = 'Ruby Gem for smarter importing of CSV Files as Array(s) of Hashes, with optional features for processing large files in parallel, embedded comments, unusual field- and record-separators, flexible mapping of CSV-headers to Hash-keys'
  gem.homepage      = "https://github.com/tilo/smarter_csv"
  gem.license       = 'MIT'

  gem.files         = `git ls-files`.split($\)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.require_paths = ["lib"]
  gem.requirements  = ['csv'] # for CSV.parse() only needed in case we have quoted fields
  gem.add_development_dependency "rspec"
  gem.add_development_dependency "simplecov"
  # gem.add_development_dependency "guard-rspec"
end
