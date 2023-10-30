# frozen_string_literal: true

require 'mkmf'
require "rbconfig"

if RbConfig::MAKEFILE_CONFIG["CFLAGS"].include?("-g -O3")
  fixed_CFLAGS = RbConfig::MAKEFILE_CONFIG["CFLAGS"].sub("-g -O3", "-O3 $(cflags)")
  puts("Fix CFLAGS: #{RbConfig::MAKEFILE_CONFIG["CFLAGS"]} -> #{fixed_CFLAGS}")
  RbConfig::MAKEFILE_CONFIG["CFLAGS"] = fixed_CFLAGS
end

CONFIG["optflags"] = "-O3"

create_makefile('smarter_csv/smarter_csv')
