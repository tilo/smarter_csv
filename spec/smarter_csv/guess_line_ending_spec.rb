# frozen_string_literal: true

require 'stringio'

# Characterization + contract tests for SmarterCSV::AutoDetection#guess_line_ending.
#
# These tests lock the contract of guess_line_ending before the implementation is
# rewritten from an IO#each_char loop to a bulk-read + regex scan. After the
# rewrite, all of these must still pass.
#
# Contract being locked in:
#   * Returns one of "\n", "\r\n", "\r"
#   * Majority wins across the scanned region
#   * Separators inside quoted regions are NOT counted (single-byte quote_char)
#   * Empty / ambiguous input returns "\n" as a safe fallback
#   * On tie or zero-found within the initial chunk, the method reads more input
#     up to a hard cap (MAX_AUTO_SCAN = 65_536 bytes)
#   * When the initial chunk ends exactly on "\r", one extra byte is read so
#     "\r\n" is never misclassified as "\r"
#   * Does not mutate the options hash

describe 'SmarterCSV::AutoDetection#guess_line_ending' do
  let(:reader) { SmarterCSV::Reader.new('something', {}) }

  def guess(io, **opts)
    options = {
      quote_char: '"',
      auto_row_sep_chars: 8192,
    }.merge(opts)
    reader.send(:guess_line_ending, io, options)
  end

  # ------------------------------------------------------------------
  # Core detection
  # ------------------------------------------------------------------
  describe 'core detection' do
    it 'returns "\n" for a file with only \n separators' do
      io = StringIO.new("a,b,c\n1,2,3\n4,5,6\n")
      expect(guess(io)).to eq "\n"
    end

    it 'returns "\r\n" for a file with only \r\n separators' do
      io = StringIO.new("a,b,c\r\n1,2,3\r\n4,5,6\r\n")
      expect(guess(io)).to eq "\r\n"
    end

    it 'returns "\r" for a file with only \r separators' do
      io = StringIO.new("a,b,c\r1,2,3\r4,5,6\r")
      expect(guess(io)).to eq "\r"
    end
  end

  # ------------------------------------------------------------------
  # Majority rule
  # ------------------------------------------------------------------
  describe 'majority rule on mixed separators' do
    it 'picks the majority when one separator dominates' do
      # 3 × "\r\n" vs 1 × "\n"
      io = StringIO.new("a\r\nb\r\nc\r\nd\ne")
      expect(guess(io)).to eq "\r\n"
    end
  end

  # ------------------------------------------------------------------
  # Quote handling — separators inside quoted fields must NOT count
  # ------------------------------------------------------------------
  describe 'quote handling' do
    it 'does not count "\n" inside a double-quoted field' do
      # 4 real "\r\n" row seps, plus 2 "\n" bytes trapped inside quoted fields.
      # If quoted "\n" counted, tally would be tied; if not, "\r\n" wins cleanly.
      csv =
        %(id,name,note\r\n) +
        %(1,"a","has\nnewline inside"\r\n) +
        %(2,"b","another\nnewline"\r\n) +
        %(3,"c","plain"\r\n)
      io = StringIO.new(csv)
      expect(guess(io)).to eq "\r\n"
    end

    it 'does not count "\r\n" inside a double-quoted field' do
      csv =
        %(id,name,note\n) +
        %(1,"a","has\r\nembedded"\n) +
        %(2,"b","another\r\nembedded"\n) +
        %(3,"c","plain"\n)
      io = StringIO.new(csv)
      expect(guess(io)).to eq "\n"
    end

    it 'respects custom quote_char "\'"' do
      csv =
        %(id,name,note\n) +
        %(1,'a','has\r\nembedded'\n) +
        %(2,'b','plain'\n) +
        %(3,'c','plain'\n)
      io = StringIO.new(csv)
      expect(guess(io, quote_char: "'")).to eq "\n"
    end

    it 'respects custom quote_char "!"' do
      csv =
        %(id,name,note\n) +
        %(1,!a!,!has\r\nembedded!\n) +
        %(2,!b!,!plain!\n) +
        %(3,!c!,!plain!\n)
      io = StringIO.new(csv)
      expect(guess(io, quote_char: '!')).to eq "\n"
    end
  end

  # ------------------------------------------------------------------
  # Long-line files (row > 500 bytes, well under 8192)
  # ------------------------------------------------------------------
  describe 'long-line files' do
    it 'correctly detects "\n" on rows that exceed 500 bytes' do
      long_row = "id,title,content\n" + (1..5).map { |i| "#{i},t,#{'x' * 1200}\n" }.join
      io = StringIO.new(long_row)
      expect(guess(io)).to eq "\n"
    end

    it 'correctly detects "\r\n" on rows that exceed 500 bytes' do
      long_row = "id,title,content\r\n" + (1..5).map { |i| "#{i},t,#{'x' * 1200}\r\n" }.join
      io = StringIO.new(long_row)
      expect(guess(io)).to eq "\r\n"
    end
  end

  # ------------------------------------------------------------------
  # Empty / fallback
  # ------------------------------------------------------------------
  describe 'empty and no-separator input' do
    it 'returns "\n" for completely empty input' do
      io = StringIO.new('')
      expect(guess(io)).to eq "\n"
    end
  end

  # ------------------------------------------------------------------
  # New behavior: grow the scan on tie or not-found
  # ------------------------------------------------------------------
  describe 'growing the scan when the initial chunk is ambiguous' do
    it 'reads more input when the initial chunk is tied, and the extra bytes break the tie' do
      # Initial chunk deliberately tied: one "\n" and one "\r\n".
      # Past the initial chunk, three more "\r\n" push "\r\n" to victory.
      initial_scan = 256
      padding = 'x' * (initial_scan - 10) # fill toward the cap
      first_chunk = "a\nb\r\n" + padding   # contains 1×"\n" + 1×"\r\n" within initial_scan bytes
      rest = "\r\nc\r\nd\r\n"              # 3 more "\r\n" past the cap
      io = StringIO.new(first_chunk + rest)
      expect(guess(io, auto_row_sep_chars: initial_scan)).to eq "\r\n"
    end

    it 'reads more input when no separator is found in the initial chunk' do
      initial_scan = 128
      no_sep_block = 'x' * (initial_scan + 50) # zero separators for well over initial_scan
      with_sep = "\r\n" * 3
      io = StringIO.new(no_sep_block + with_sep)
      expect(guess(io, auto_row_sep_chars: initial_scan)).to eq "\r\n"
    end

    it 'warns and returns "\n" fallback when no known separator is found within the hard cap' do
      # 70 KB of data with zero known separators anywhere — exceeds MAX_AUTO_SCAN (64 KB).
      # This models an exotic-separator file (e.g. iTunes-style "\u2028").
      io = StringIO.new('x' * 70_000)
      result = nil
      expect { result = guess(io) }.to output(/no row separator found/).to_stderr
      expect(result).to eq "\n"
    end

    it 'warns and returns "\n" fallback when a file uses an exotic separator like \u2028' do
      # Build a file that uses U+2028 (Line Separator) as its row separator.
      # It's multi-byte in UTF-8 (0xE2 0x80 0xA8) and does not contain any "\r"
      # or "\n" bytes — so none of the known separator counts can ever be > 0.
      rows = (1..200).map { |i| "id#{i},name#{i},note#{i}\u2028" }.join
      io = StringIO.new(rows)
      result = nil
      expect { result = guess(io) }.to output(/no row separator found/).to_stderr
      expect(result).to eq "\n"
    end

    it 'resolves a near-tie silently when a chunk-boundary artifact tips one count by 1' do
      # Equal numbers of "\n" and "\r\n" alternating in the source. With the
      # default 8192-byte chunk size, the scan stops mid-block at iteration 3
      # with lf = crlf + 1 — a boundary artifact, not real signal. The majority
      # rule (winner > sum of others) treats +1 as a win and returns "\n"
      # without warning. This is a known, accepted limitation of the margin-1
      # rule on degenerate inputs.
      row = "a,b,c"
      block = "#{row}\n#{row}\r\n" # 1× "\n" + 1× "\r\n" per pair, 13 bytes
      io = StringIO.new(block * 6000) # 78 KB
      result = nil
      expect { result = guess(io) }.not_to output.to_stderr
      result = guess(StringIO.new(block * 6000))
      expect(result).to eq "\n"
    end

    it 'warns and returns "\n" fallback when a truly tied stream reaches the hard cap' do
      # Repeating unit "\n\r\n" keeps counts exactly tied at every chunk boundary:
      # each 8192-byte read ends on "\r", the existing extra-byte read pulls in
      # the following "\n", and the buffer lands on a whole-block boundary with
      # 1× "\n" and 1× "\r\n" per 3 bytes. After ~8 iterations the 64 KB cap is
      # hit with counts still equal, exercising the warn-and-fallback path.
      io = StringIO.new("\n\r\n" * 25_000) # 75 KB — past 64 KB cap
      result = nil
      expect { result = guess(io) }.to output(/no clear row separator/).to_stderr
      expect(result).to eq "\n"
    end

    it 'does not warn when verbose: :quiet' do
      io = StringIO.new('x' * 70_000)
      expect { guess(io, verbose: :quiet) }.not_to output.to_stderr
    end
  end

  # ------------------------------------------------------------------
  # "\r" at the chunk boundary must be disambiguated
  # ------------------------------------------------------------------
  describe '\r at the chunk boundary' do
    it 'does not misclassify "\r\n" as "\r" when the chunk ends on "\r"' do
      # Initial scan size chosen so the first chunk ends EXACTLY on "\r".
      # Old implementation bumped counts["\r"] post-loop and could mis-pick "\r".
      # New implementation must read one more byte and see the "\n" that follows.
      # Input:  "aaaa...aaa\r" = initial_scan bytes, then "\n..." continues
      initial_scan = 16
      body_before_r = 'a' * (initial_scan - 1) + "\r"
      rest = "\nsecond\r\nthird\r\n"
      io = StringIO.new(body_before_r + rest)
      expect(guess(io, auto_row_sep_chars: initial_scan)).to eq "\r\n"
    end
  end

  # ------------------------------------------------------------------
  # Invariants
  # ------------------------------------------------------------------
  describe 'invariants' do
    it 'does not mutate the options hash' do
      io = StringIO.new("a,b,c\n1,2,3\n")
      opts = { quote_char: '"', auto_row_sep_chars: 8192 }
      frozen_snapshot = opts.dup.freeze
      reader.send(:guess_line_ending, io, opts)
      expect(opts).to eq(frozen_snapshot)
    end

    it 'always returns one of "\n", "\r\n", "\r"' do
      io = StringIO.new("a,b,c\n1,2,3\n")
      expect(["\n", "\r\n", "\r"]).to include(guess(io))
    end
  end
end
