# frozen_string_literal: true

require 'spec_helper'
require 'stringio'

# Differential C/Ruby parity fuzz (seeded, deterministic).
#
# Feeds both paths (acceleration: true / false) the same pseudo-random CSV-ish inputs and
# asserts they produce byte-identical results — same rows, same value classes — or raise
# the same error class. This is the net that catches parity breaks hand-written corner
# cases miss: it found the mid-character byteindex crash (multi-byte char before a literal
# quote) and the trailing-\r line-terminator divergence that shipped in 1.19.0's fixes.
#
# Deterministic by construction: fixed Random seeds, fixed alphabets and option sets —
# every run tests the exact same inputs, so a failure is always reproducible. The failure
# message prints the diverging input verbatim for direct paste into a regression test.
describe 'C/Ruby parity fuzz (seeded)' do
  # Alphabet A: broad mix — digits, separators, quotes, whitespace, exponent letters,
  # signs, a multi-byte character, backslash, and \r.
  ALPHABET_BROAD = ['a', 'b', '1', '2', '0', '.', ',', '"', "\n", ' ', "\t", 'e', 'E', '-', '+', 'é', '\\', "\r"].freeze

  # Alphabet B: adversarial mix — heavy on quotes, \r, backslash, and multi-byte chars,
  # the ingredients of every real divergence found so far.
  ALPHABET_QUOTES = ['a', '0', ',', '"', "\n", "\r", ' ', 'é', '\\', '.', '-'].freeze

  OPTION_SETS = [
    {},
    { strip_whitespace: false },
    { remove_empty_values: false },
    { remove_empty_hashes: false },
    { remove_zero_values: true },
    { quote_boundary: :legacy },
    { quote_escaping: :backslash },
    { row_sep: "\n" },
    { convert_values_to_numeric: false },
    { strings_as_keys: true },
    { keep_original_headers: true },
    # Combined sets — some corners are only reachable when options interact
    { strip_whitespace: false, remove_empty_values: false },
    { strip_whitespace: false, remove_zero_values: true },
    { remove_empty_values: false, remove_empty_hashes: false },
    { quote_escaping: :backslash, quote_boundary: :legacy },
    { quote_escaping: :backslash, strip_whitespace: false },
    { strings_as_keys: true, strip_whitespace: false, remove_empty_values: false },
  ].freeze

  def run_path(data, opts, accel)
    result = SmarterCSV.process(StringIO.new(data.dup), opts.merge(acceleration: accel, verbose: :quiet))
    # Include value classes so 42 / 42.0 / "42" count as different results.
    [:ok, result.inspect, result.flat_map { |h| h.values.map(&:class) }.inspect]
  rescue StandardError => e
    [:error, e.class.to_s]
  end

  def fuzz(seed, cases, alphabet, rows_per_case)
    rng = Random.new(seed)
    cases.times do |n|
      rows = 1 + rng.rand(rows_per_case)
      body = Array.new(rows) { Array.new(2 + rng.rand(30)) { alphabet[rng.rand(alphabet.size)] }.join }.join("\n")
      data = "h1,h2\n#{body}\n"
      opts = OPTION_SETS[rng.rand(OPTION_SETS.size)]

      c_result    = run_path(data, opts, true)
      ruby_result = run_path(data, opts, false)
      next if c_result == ruby_result

      raise "C/Ruby parity divergence (seed #{seed}, case #{n}):\n" \
            "  input: #{data.inspect}\n  options: #{opts.inspect}\n" \
            "  C:    #{c_result.inspect}\n  Ruby: #{ruby_result.inspect}"
    end
  end

  it 'produces identical results on both paths across the broad alphabet' do
    expect { fuzz(4242, 1000, ALPHABET_BROAD, 2) }.not_to raise_error
  end

  it 'produces identical results on both paths across the quote-heavy alphabet' do
    expect { fuzz(77, 1000, ALPHABET_QUOTES, 3) }.not_to raise_error
  end
end
