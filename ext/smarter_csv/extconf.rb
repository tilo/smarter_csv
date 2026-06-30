# frozen_string_literal: true

require 'mkmf'
require "rbconfig"
require_relative 'cpu_flags'

if RbConfig::MAKEFILE_CONFIG["CFLAGS"].include?("-g -O3")
  fixed_CFLAGS = RbConfig::MAKEFILE_CONFIG["CFLAGS"].sub("-g -O3", "-O3 $(cflags)")
  puts("Fix CFLAGS: #{RbConfig::MAKEFILE_CONFIG["CFLAGS"]} -> #{fixed_CFLAGS}")
  RbConfig::MAKEFILE_CONFIG["CFLAGS"] = fixed_CFLAGS
end

# Probe whether the compiler accepts a flag by compiling a trivial program with
# it. Lets us skip flags the toolchain rejects (e.g. -march=native on Clang/ARM,
# or GCC-only flags on MSVC) instead of breaking the build. Replaces the old
# RUBY_PLATFORM string guesses: ask the actual compiler, don't infer from the OS.
def compiler_accepts?(flag)
  try_compile("int main(void){return 0;}", flag)
end

optflags = "-O3 -flto -fomit-frame-pointer -DNDEBUG".dup

# CPU optimization level, set via SMARTER_CSV_PERFORMANCE (default: portable).
# See cpu_flags.rb for the full description of each level.
#
#   portable (default) - no host-specific flags; runs on any CPU of the same arch.
#   tuned              - -mtune=native; host scheduling tuning, still portable.
#   max                - host instruction set (-march/-mcpu native); fastest, but
#                        NOT portable -- may crash on a CPU lacking those instructions.
cpu = SmarterCSV::CpuFlags.select(ENV["SMARTER_CSV_PERFORMANCE"], accepts: method(:compiler_accepts?))
warn(cpu[:warning]) if cpu[:warning]
cpu[:flags].each { |flag| optflags << " #{flag}" }
puts("SmarterCSV performance level: #{cpu[:level]} -- optflags: #{optflags}")

# -fno-semantic-interposition: GCC/Clang only (not MSVC). Allows intra-library
# calls to bypass the PLT on Linux and enables more aggressive LTO inlining.
optflags << " -fno-semantic-interposition" if compiler_accepts?("-fno-semantic-interposition")

append_cflags('-Wno-compound-token-split-by-macro')

CONFIG["optflags"] = optflags
CONFIG["debugflags"] = ""

create_makefile('smarter_csv/smarter_csv')
