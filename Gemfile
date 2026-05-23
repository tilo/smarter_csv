# frozen_string_literal: true

source 'https://rubygems.org'

# Specify your gem's dependencies in smarter_csv.gemspec
gemspec

group :development do
  gem "rake"
  gem "rake-compiler"
  gem "ostruct"          # silences rake's stdlib-deprecation warning during dev
  gem "rubocop"
end

group :development, :test do
  gem "awesome_print"
  gem "pry"              # required in spec_helper.rb; also useful in dev console
end

group :test do
  gem "rspec"
  gem "simplecov"
  gem "parallel"      # used by spec/features/parallel_gem_slicing_spec.rb to demonstrate Parallel.each fan-out
  gem "sidekiq"       # used by spec/features/sidekiq_slicing_spec.rb to demonstrate Sidekiq worker pattern (via Sidekiq::Testing.inline!)
  gem "activesupport" # used by spec/features/sidekiq_slicing_spec.rb for Hash#deep_symbolize_keys (the canonical way to recover symbol keys after Sidekiq's JSON roundtrip)
end
