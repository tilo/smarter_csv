# frozen_string_literal: true

require 'mkmf'
require "rbconfig"

# On non-MRI Rubies (JRuby, TruffleRuby, ...) there is no C extension to build, and trying to build
# it breaks `gem install` for anything that depends on smarter_csv. Write a no-op Makefile so install
# succeeds, then stop. At runtime SmarterCSV falls back to its pure-Ruby parser (it checks whether the
# C functions actually loaded via respond_to?(:parse_csv_line_c)).
if RUBY_ENGINE != 'ruby'
  File.write('Makefile', dummy_makefile($srcdir).join)
  exit 0
end

if RbConfig::MAKEFILE_CONFIG["CFLAGS"].include?("-g -O3")
  fixed_CFLAGS = RbConfig::MAKEFILE_CONFIG["CFLAGS"].sub("-g -O3", "-O3 $(cflags)")
  puts("Fix CFLAGS: #{RbConfig::MAKEFILE_CONFIG["CFLAGS"]} -> #{fixed_CFLAGS}")
  RbConfig::MAKEFILE_CONFIG["CFLAGS"] = fixed_CFLAGS
end

optflags = "-O3 -flto -fomit-frame-pointer -DNDEBUG".dup
optflags << " -march=native" unless RUBY_PLATFORM.start_with?("arm64-darwin")
# -fno-semantic-interposition: GCC/Clang only (not MSVC). Allows intra-library
# calls to bypass the PLT on Linux and enables more aggressive LTO inlining.
optflags << " -fno-semantic-interposition" unless RUBY_PLATFORM.include?("mswin")

append_cflags('-Wno-compound-token-split-by-macro')

CONFIG["optflags"] = optflags
CONFIG["debugflags"] = ""

create_makefile('smarter_csv/smarter_csv')
