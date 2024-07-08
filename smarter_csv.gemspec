# coding: utf-8
# frozen_string_literal: true

require File.expand_path('lib/smarter_csv/version', __dir__)

Gem::Specification.new do |spec|
  spec.name          = "smarter_csv"
  spec.version       = SmarterCSV::VERSION
  spec.authors       = ["Tilo Sloboda"]
  spec.email         = ["tilo.sloboda@gmail.com"]

  spec.summary       = "Convenient CSV Reading and Writing"
  spec.description   = "Ruby Gem for convenient reading and writing of CSV files. It has intelligent defaults, and auto-discovery of column and row separators. It imports CSV Files as Array(s) of Hashes, suitable for direct processing with ActiveRecord, kicking-off batch jobs with Sidekiq, parallel processing, or oploading data to S3. Similarly, writing CSV files takes Hashes, or Arrays of Hashes to create a CSV file."
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
  spec.add_development_dependency "codecov"
  spec.add_development_dependency "pry"
  spec.add_development_dependency "rspec"
  spec.add_development_dependency "rubocop"
  spec.add_development_dependency "simplecov"
end
