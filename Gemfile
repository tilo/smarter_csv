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
end
