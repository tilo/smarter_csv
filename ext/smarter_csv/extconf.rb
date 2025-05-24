# frozen_string_literal: true

require 'mkmf'
require "rbconfig"

if RbConfig::MAKEFILE_CONFIG["CFLAGS"].include?("-g -O3")
  fixed_CFLAGS = RbConfig::MAKEFILE_CONFIG["CFLAGS"].sub("-g -O3", "-O3 $(cflags)")
  puts("Fix CFLAGS: #{RbConfig::MAKEFILE_CONFIG["CFLAGS"]} -> #{fixed_CFLAGS}")
  RbConfig::MAKEFILE_CONFIG["CFLAGS"] = fixed_CFLAGS
end

# CONFIG["optflags"] = "-O3 -march=native -flto"
CONFIG["optflags"] = "-O3 -march=native -flto -fomit-frame-pointer -DNDEBUG"
CONFIG["debugflags"] = ""

$INSTALLFILES = [['smarter_csv.bundle', 'lib']]

create_makefile('smarter_csv')

