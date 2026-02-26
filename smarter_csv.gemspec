# coding: utf-8
# frozen_string_literal: true

require File.expand_path('lib/smarter_csv/version', __dir__)

Gem::Specification.new do |spec|
  spec.name          = "smarter_csv"
  spec.authors       = ["Tilo Sloboda"]
  spec.email         = ["tilo.sloboda@gmail.com"]
  spec.version       = SmarterCSV::VERSION
  spec.date          = Time.now.utc.strftime('%Y-%m-%d')

  spec.summary = "Fastest end-to-end CSV ingestion for Ruby with smart defaults and Rails-ready hash output"
  spec.description = <<~DESC
    SmarterCSV is a high-performance CSV reader and writer for Ruby focused on
    fastest end-to-end ingestion — not just parsing. It returns ready-to-use
    hashes with configurable header and value transformations, intelligent
    defaults, and automatic delimiter discovery.

    Built for real-world data pipelines, SmarterCSV supports chunked processing
    for large files, streaming via Enumerable APIs, and C acceleration
    to optimize the full ingestion path (parsing + hash construction +
    conversions).

    Designed to handle messy user-uploaded CSV while remaining easy to integrate
    with Rails, ActiveRecord imports, Sidekiq jobs, parallel processing, and
    S3-based workflows.
  DESC

  spec.homepage      = "https://github.com/tilo/smarter_csv"
  spec.license       = 'MIT'

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "https://github.com/tilo/smarter_csv/blob/main/CHANGELOG.md"

  spec.required_ruby_version = ">= 2.5.0"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (f == __FILE__) ||
        f.match(%r{\A(?:(?:bin|test|spec|features)/|\.(?:git|travis|circleci)|appveyor)}) || f.match(/\.h\z/)
    end
  end
  spec.test_files = spec.files.grep(%r{^(test|spec|features)/})

  spec.executables   = spec.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  spec.require_paths = %w[lib ext]
  spec.extensions = ["ext/smarter_csv/extconf.rb"]
  spec.files += Dir.glob("ext/smarter_csv/**/*")

  spec.add_development_dependency "awesome_print"
  spec.add_development_dependency "pry"
  spec.add_development_dependency "rspec"
  spec.add_development_dependency "rubocop"
  spec.add_development_dependency "simplecov"
end
