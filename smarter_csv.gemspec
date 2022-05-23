# -*- encoding: utf-8 -*-
require File.expand_path('../lib/smarter_csv/version', __FILE__)

Gem::Specification.new do |spec|
  spec.name          = "smarter_csv"
  spec.version       = SmarterCSV::VERSION
  spec.authors       = ["Tilo Sloboda"]
  spec.email         = ["tilo.sloboda@gmail.com"]

  spec.summary       = %q{Ruby Gem for smarter importing of CSV Files (and CSV-like files), with lots of optional features, e.g. chunked processing for huge CSV files}
  spec.description   = %q{Ruby Gem for smarter importing of CSV Files as Array(s) of Hashes, with optional features for processing large files in parallel, embedded comments, unusual field- and record-separators, flexible mapping of CSV-headers to Hash-keys}
  spec.homepage      = "https://github.com/tilo/smarter_csv"
  spec.license       = 'MIT'

  spec.files         = `git ls-files`.split($\)
  spec.executables   = spec.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]
  spec.add_development_dependency "pry"
  spec.add_development_dependency "rspec"
  spec.add_development_dependency "simplecov"
  spec.add_development_dependency "codecov", require: false, group: :test
  spec.add_development_dependency "awesome_print"
#  spec.add_development_dependency "rake-compiler"
#  spec.add_development_dependency "rake-compiler-dock"

  spec.metadata["homepage_uri"] = spec.homepage

  spec.extensions << "ext/smarter_csv/extconf.rb"
end
