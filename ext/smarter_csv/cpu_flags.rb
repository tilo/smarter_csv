# frozen_string_literal: true

module SmarterCSV
  # Pure (mkmf-free) selection of CPU-optimization flags from the
  # SMARTER_CSV_PERFORMANCE environment variable. Kept separate from extconf.rb
  # so the logic can be unit-tested without invoking a compiler.
  #
  # Levels:
  #   portable - no host-specific flags. The binary runs on any CPU of the same
  #              architecture. The safe default: a binary built here will not
  #              crash with "Illegal instruction" on an older/different CPU.
  #   tuned    - -mtune=native: tunes instruction scheduling for the build host's
  #              microarchitecture WITHOUT changing the instruction set, so the
  #              binary stays portable. A real win when build and run hosts share
  #              a microarchitecture (same chip or a homogeneous fleet).
  #   max      - host-specific instructions: -march=native, or -mcpu=native on
  #              ARM/Clang where -march=native is rejected. Fastest, but NOT
  #              portable -- may crash on a CPU lacking the build host's
  #              instructions. Use only when build host and run host match.
  #
  # `accepts` is a predicate (in the real build, a wrapper over mkmf's
  # try_compile) returning true when the compiler accepts a given flag; each
  # candidate is probed so an unsupported flag is skipped rather than breaking
  # the build.
  module CpuFlags
    LEVELS = %w[portable tuned max].freeze

    # Candidate flags per level, in preference order. The first one the compiler
    # accepts wins. `max` degrades march -> mcpu -> mtune; tuned only ever
    # considers -mtune=native (never an instruction-set flag).
    CANDIDATES = {
      'portable' => [].freeze,
      'tuned' => ['-mtune=native'].freeze,
      'max' => ['-march=native', '-mcpu=native', '-mtune=native'].freeze,
    }.freeze

    # Returns a Hash: { level: String, flags: Array<String>, warning: String|nil }.
    def self.select(raw_level, accepts:)
      level, warning = normalize(raw_level)
      chosen = CANDIDATES[level].find { |flag| accepts.call(flag) }
      { level: level, flags: chosen ? [chosen] : [], warning: warning }
    end

    # Normalizes the env value to a known level. Unknown values fall back to
    # 'portable' (a typo can then only ever be slower, never non-portable) and
    # return a warning naming the bad value and the fallback.
    def self.normalize(raw_level)
      value = raw_level.to_s.strip.downcase
      return ['portable', nil] if value.empty?
      return [value, nil] if LEVELS.include?(value)

      ['portable', "SMARTER_CSV_PERFORMANCE=#{raw_level.inspect} is not one of #{LEVELS.join('|')}; using 'portable'."]
    end
  end
end
