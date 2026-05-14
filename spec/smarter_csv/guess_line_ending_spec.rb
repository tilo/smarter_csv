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
#     up to a hard cap (MAX_AUTO_ROW_SEP_CHARS = 65_536 bytes)
#   * When the initial chunk ends exactly on "\r", one extra byte is read so
#     "\r\n" is never misclassified as "\r"
#   * Does not mutate the options hash

describe 'SmarterCSV::AutoDetection#guess_line_ending' do
  let(:reader) { SmarterCSV::Reader.new('something', {}) }

  def guess(io, **opts)
    options = {
      quote_char: '"',
      auto_row_sep_chars: SmarterCSV::AutoDetection::MIN_AUTO_ROW_SEP_CHARS,
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
      # 70 KB of data with zero known separators anywhere — exceeds MAX_AUTO_ROW_SEP_CHARS (64 KB).
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
      # Period-4 unit "\nx\rx" gives 1 lone \n and 1 lone \r per 4 bytes (no \r\n).
      # All adaptive doubling chunk sizes (512, 1024, 2048, 4096, 8192) are
      # multiples of 4, so every read boundary lands cleanly on unit-end and
      # the counts (lf == cr, crlf == 0) stay tied through every check until
      # MAX_AUTO_ROW_SEP_CHARS is reached, exercising the warn-and-fallback path.
      io = StringIO.new("\nx\rx" * 17_500) # 70 KB — past 64 KB cap
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

  # ------------------------------------------------------------------
  # record_warning contract — verifies the wrapper API at the call-site
  # boundary, independent of where the warning eventually lands (stderr
  # today, potentially Rails.logger tomorrow).
  # ------------------------------------------------------------------
  describe 'record_warning contract' do
    context 'when zero known separators are found past the hard cap' do
      it 'calls record_warning with :row_sep / :no_row_sep_found at :error severity' do
        io = StringIO.new('x' * 70_000)
        expect(reader).to receive(:record_warning)
          .with(type: :row_sep, code: :no_row_sep_found, severity: :error).and_call_original
        guess(io)
      end

      it 'yields a message containing "no row separator found"' do
        io = StringIO.new('x' * 70_000)
        expect(reader).to receive(:record_warning) do |**_kwargs, &block|
          expect(block.call).to match(/no row separator found/)
        end
        guess(io)
      end
    end

    context 'when an exotic separator like \u2028 is used' do
      it 'calls record_warning with :row_sep / :no_row_sep_found at :error severity' do
        rows = (1..200).map { |i| "id#{i},name#{i},note#{i}\u2028" }.join
        io = StringIO.new(rows)
        expect(reader).to receive(:record_warning)
          .with(type: :row_sep, code: :no_row_sep_found, severity: :error).and_call_original
        guess(io)
      end
    end

    context 'when a true tie between known separators reaches the hard cap' do
      it 'calls record_warning with :row_sep / :no_clear_row_sep at :error severity' do
        io = StringIO.new("\nx\rx" * 17_500)
        expect(reader).to receive(:record_warning)
          .with(type: :row_sep, code: :no_clear_row_sep, severity: :error).and_call_original
        guess(io)
      end

      it 'yields a message containing "no clear row separator"' do
        io = StringIO.new("\nx\rx" * 17_500)
        expect(reader).to receive(:record_warning) do |**_kwargs, &block|
          expect(block.call).to match(/no clear row separator/)
        end
        guess(io)
      end
    end

    context 'when verbose: :quiet' do
      it 'does not call record_warning on zero-separator input' do
        io = StringIO.new('x' * 70_000)
        expect(reader).not_to receive(:record_warning)
        guess(io, verbose: :quiet)
      end

      it 'does not call record_warning on a truly tied stream past the cap' do
        io = StringIO.new("\nx\rx" * 17_500)
        expect(reader).not_to receive(:record_warning)
        guess(io, verbose: :quiet)
      end
    end

    context 'when detection succeeds with a clear majority' do
      it 'does not call record_warning on a "\n"-only file' do
        io = StringIO.new("a,b,c\n1,2,3\n4,5,6\n")
        expect(reader).not_to receive(:record_warning)
        guess(io)
      end

      it 'does not call record_warning when a near-tie is resolved by the margin-1 rule' do
        row = "a,b,c"
        block = "#{row}\n#{row}\r\n"
        io = StringIO.new(block * 6000)
        expect(reader).not_to receive(:record_warning)
        guess(io)
      end
    end

    # --- histogram collection ----------------------------------------
    context 'histogram collection into reader.warnings' do
      it 'populates reader.warnings with a record on first occurrence' do
        io = StringIO.new('x' * 70_000)
        guess(io)
        expect(reader.warnings.size).to eq 1
        w = reader.warnings.first
        expect(w[:type]).to eq :row_sep
        expect(w[:code]).to eq :no_row_sep_found
        expect(w[:count]).to eq 1
        expect(w[:message]).to match(/no row separator found/)
      end

      it 'dedupes repeat (type, code) into count, not new records' do
        3.times { guess(StringIO.new('x' * 70_000)) }
        expect(reader.warnings.size).to eq 1
        expect(reader.warnings.first[:count]).to eq 3
      end

      it 'stores distinct (type, code) pairs as separate records' do
        guess(StringIO.new('x' * 70_000))       # :no_row_sep_found
        guess(StringIO.new("\nx\rx" * 17_500))  # :no_clear_row_sep
        codes = reader.warnings.map { |w| w[:code] }
        expect(codes).to contain_exactly(:no_row_sep_found, :no_clear_row_sep)
        expect(reader.warnings.map { |w| w[:count] }).to all(eq(1))
      end

      it 'does not re-emit to the sink on dedup hits' do
        allow(reader).to receive(:warn)
        2.times { guess(StringIO.new('x' * 70_000)) }
        expect(reader).to have_received(:warn).once
      end

      it 'does not allocate the message on dedup hits' do
        # First call allocates. Second call must not invoke the block.
        guess(StringIO.new('x' * 70_000))
        calls = 0
        reader.send(:record_warning, type: :row_sep, code: :no_row_sep_found) do
          calls += 1
          'lazy message'
        end
        expect(calls).to eq 0
      end
    end
  end

  # Adaptive scan: the first read is auto_row_sep_chars bytes (default = MIN
  # = 512). Iter 2 reuses the iter-1 size; iter 3+ doubles each iteration up
  # to MAX_AUTO_ROW_SEP_CHARS. Common files (clear majority within ~50 bytes)
  # resolve at iter 1; ambiguous files escalate.
  describe 'adaptive scan chunk sizing' do
    # Tracks bytes requested per read() call so we can verify the read pattern.
    class TrackingIO
      attr_reader :read_sizes

      def initialize(content)
        @io = StringIO.new(content)
        @read_sizes = []
      end

      def read(n)
        @read_sizes << n
        @io.read(n)
      end
    end

    let(:min_arc) { SmarterCSV::AutoDetection::MIN_AUTO_ROW_SEP_CHARS }

    it 'first read uses auto_row_sep_chars (default = MIN_AUTO_ROW_SEP_CHARS = 512)' do
      content = "a,b\n" + (1..50).map { |i| "x_#{i},y_#{i}\n" }.join # ~600 bytes, clear LF majority
      io = TrackingIO.new(content)
      result = guess(io) # uses helper default = MIN_AUTO_ROW_SEP_CHARS
      expect(result).to eq("\n")
      expect(io.read_sizes.first).to eq(min_arc)
    end

    it 'returns from the first chunk when separator is unambiguous (no escalation)' do
      content = "a,b\n" + (1..30).map { |i| "x_#{i},y_#{i}\n" }.join # well under 512 bytes
      io = TrackingIO.new(content)
      guess(io)
      # Only the initial chunk was read; loop returned on first iteration.
      # (May include a 1-byte read for the \r-straddle check, but no further chunk reads.)
      large_reads = io.read_sizes.reject { |n| n == 1 }
      expect(large_reads.size).to eq(1)
      expect(large_reads.first).to eq(min_arc)
    end

    it 'doubles the chunk size starting at iter 3 when first chunks are ambiguous' do
      # Period-4 tie unit ("\nx\rx") for the first 1024 bytes — kept tied at every
      # multiple-of-4 read boundary — then a clear LF tail that resolves at iter 3.
      tie_region = "\nx\rx" * 256  # 1024 bytes of perfect lf/cr tie (crlf=0)
      tail       = "a\n" * 200     # 400 bytes of pure LF
      io         = TrackingIO.new(tie_region + tail)
      guess(io)
      large_reads = io.read_sizes.reject { |n| n == 1 }
      expect(large_reads[0]).to eq(512)   # iter 1: auto_row_sep_chars
      expect(large_reads[1]).to eq(512)   # iter 2: same as iter 1
      expect(large_reads[2]).to eq(1024)  # iter 3: doubled
    end

    it 'follows the doubling pattern through many iterations on long ambiguous files' do
      # 64KB of period-4 tie forces the loop to run until MAX_AUTO_ROW_SEP_CHARS.
      tie_region = "\nx\rx" * 16_384 # 65536 bytes of perfect tie
      io         = TrackingIO.new(tie_region)
      expect { guess(io) }.to output(/no clear row separator/).to_stderr
      large_reads = io.read_sizes.reject { |n| n == 1 }
      # Doubling: 512, 512, 1024, 2048, 4096, 8192, 16384, 32768
      # After iter 8 (cumulative 65536), loop breaks via MAX_AUTO_ROW_SEP_CHARS.
      expect(large_reads.first(8)).to eq([512, 512, 1024, 2048, 4096, 8192, 16_384, 32_768])
    end

    it 'clamps first read to MAX_AUTO_ROW_SEP_CHARS even when auto_row_sep_chars is larger' do
      max_arc = SmarterCSV::AutoDetection::MAX_AUTO_ROW_SEP_CHARS
      content = "a,b\n" + (1..100).map { |i| "x_#{i},y_#{i}\n" }.join
      io = TrackingIO.new(content)
      # Pass auto_row_sep_chars larger than MAX
      result = guess(io, auto_row_sep_chars: max_arc + 10_000)
      expect(result).to eq("\n")
      # First read should be capped at max_arc, not max_arc + 10_000
      expect(io.read_sizes.first).to be <= max_arc
    end

    it 'respects MAX_AUTO_ROW_SEP_CHARS hard cap on total bytes read' do
      max_arc = SmarterCSV::AutoDetection::MAX_AUTO_ROW_SEP_CHARS
      # Create a long ambiguous file; scan will attempt to read up to MAX
      tie_region = "\nx\rx" * (max_arc / 4)
      io = TrackingIO.new(tie_region)
      guess(io)
      large_reads = io.read_sizes.reject { |n| n == 1 }
      # Total should not exceed max_arc (plus the accumulated doubling up to the cap)
      cumulative = 0
      large_reads.each do |read_size|
        cumulative += read_size
        break if cumulative >= max_arc
      end
      expect(cumulative).to be <= max_arc
    end
  end

  # Single-pass byte-level scan: each chunk is scanned only once and counts
  # accumulate across iterations. The state that must persist between chunks:
  #   * crlf, lf, cr running counts
  #   * in_quote (separators inside a quoted region are not counted)
  #   * pending_cr (a "\r" at chunk end is deferred so it can pair with a "\n"
  #     starting the next chunk to form one "\r\n", not two separate seps).
  #
  # These tests use small auto_row_sep_chars values so a chunk boundary lands
  # at a known byte position in short test content. stub_const lowers the
  # defensive floor so the small values aren't clamped up.
  describe 'chunk-boundary scanning (incremental, no cumulative re-scan)' do
    before { stub_const('SmarterCSV::AutoDetection::MIN_AUTO_ROW_SEP_CHARS', 1) }

    it 'pairs a deferred "\r" with a "\n" at the start of the next chunk as crlf' do
      # 11 bytes: "name,value\r" — chunk1 ends exactly on \r.
      # Then "\nitem,1\nitem,2\n..." — chunk2 begins with \n.
      content = "name,value\r\n" + (1..50).map { |i| "x_#{i},y_#{i}\r\n" }.join
      io = StringIO.new(content)
      expect(guess(io, auto_row_sep_chars: 11)).to eq("\r\n")
    end

    it 'resolves a deferred "\r" as cr at the start of iter 2 when chunk 2 does not begin with "\n"' do
      # iter 1 (chunk_size=7) reads "a\rb\r\nx\r" → cr=1, crlf=1 (tied),
      #   pending_cr=true at end of chunk.
      # iter 2 reads "yz\rfoo\r" — first byte 'y' is not \n, so the deferred
      #   "\r" is counted as a lone cr (line covered: pending_cr → cr branch).
      # Final majority: cr=3, crlf=1 → returns "\r".
      content = "a\rb\r\nx\ryz\rfoo\r"
      io = StringIO.new(content)
      expect(guess(io, auto_row_sep_chars: 7)).to eq("\r")
    end

    it 'counts a deferred "\r" as a lone cr when the next chunk does not start with "\n"' do
      # Many lone \r between letters, plus four \r\n. The chunk boundary lands
      # on a non-separator byte so no straddle is involved here — this verifies
      # that lone \r within a chunk is counted as cr. Counts: 5 lone \r, 4 \r\n.
      # cr (5) > lf+crlf (0+4) → result must be "\r".
      content = "a\rb\rc\rd\re\rf\r\nname,val\r\nname,val\r\nname,val\r\n"
      io = StringIO.new(content)
      expect(guess(io, auto_row_sep_chars: 12)).to eq("\r")
    end

    it 'counts a deferred "\r" as cr when EOF arrives before any next byte' do
      # File ends in a lone "\r" with no following "\n". Counts as cr.
      io = StringIO.new("name,val\r")
      expect(guess(io, auto_row_sep_chars: 9)).to eq("\r")
    end

    it 'does not count separators inside a quoted region that spans chunks' do
      # The quoted field "abc\ndef\nghi" contains two \n bytes that must NOT
      # be counted. The two real row separators are the \r\n after the quote
      # and the trailing \r\n. Force a small chunk so the open quote is in
      # chunk 1 and the close quote is in chunk 2.
      content = %{a,"abc\ndef\nghi"\r\nb,c\r\n}
      io = StringIO.new(content)
      # auto_row_sep_chars=8 → chunk1 cuts the quoted region in half.
      expect(guess(io, auto_row_sep_chars: 8)).to eq("\r\n")
    end

    it 'handles doubled quotes inside a quoted field correctly' do
      # "a""b" — the doubled quotes naturally toggle in_quote off/on without
      # any special-case code. The \n inside is still inside the quoted field.
      content = %{c1,c2\n"a""b\nc","d"\n"x","y"\n"u","v"\n}
      io = StringIO.new(content)
      expect(guess(io, auto_row_sep_chars: 12)).to eq("\n")
    end

    it 'respects a custom quote_char' do
      # Use single-quote as quote_char. Inside the quoted region, \n must not
      # be counted as a row separator.
      content = "h1,h2\n'a\nb','c'\n'x','y'\n'u','v'\n'p','q'\n"
      io = StringIO.new(content)
      expect(guess(io, auto_row_sep_chars: 7, quote_char: "'")).to eq("\n")
    end

    it 'handles a chunk that is entirely inside an unclosed quoted region' do
      # chunk1 opens a quote that doesn't close → in_quote=true at end.
      # chunk2 is ENTIRELY inside the still-open quote (no close byte) → the
      # whole chunk is dropped (part = nil branch). chunk3 finally closes.
      # The two real \n separators (after the close-quote and at EOF) win.
      content = %{a,"OPEN_xxxxxxxxxxxxxxxxxxxxxxxxxx_CLOSE"\nb,c\n}
      io = StringIO.new(content)
      # chunk_size=10:
      #   c1: 'a,"OPEN_xx'              → in_quote=true after strip
      #   c2: 'xxxxxxxxxx'              → entirely inside quote → part = nil
      #   c3: 'xxxxxxxxxx'              → still inside quote → part = nil
      #   c4: 'xxxx_CLOSE'              → still no close → part = nil
      #   c5: '"\nb,c\n'                → close found, then 2× \n counted
      expect(guess(io, auto_row_sep_chars: 10)).to eq("\n")
    end

    it 'counts a trailing "\r" as cr (not deferred) when an unclosed open quote follows it in the same chunk' do
      # Chunk1 ends with: ..."\r" + open-quote + content-to-EOS. After the gsub
      # strips the open-quote-to-EOS, unquoted ends in "\r" AND in_quote=true.
      # The byte right after the "\r" in the original chunk was the open-quote
      # (not "\n"), so the "\r" is a lone cr — counting it now is correct;
      # deferring would mispair against the next chunk's first byte (which is
      # inside the still-open quote). One \r\n earlier in chunk1 keeps the
      # post-chunk-1 majority indeterminate (crlf=1, cr=1, tied) so the loop
      # continues into chunk2 instead of bailing on a 1-vs-0 majority.
      content = "a,b\r\nc,d\r\"unclosed_to_chunk_end_padding_zzz\nclose\"\r\nz,w\r\nq,r\r\n"
      io = StringIO.new(content)
      # chunk_size=30 keeps the boundary inside the quoted region (the close
      # quote is at byte 49) so chunk1's quote-count stays odd:
      #   chunk1 = 'a,b\r\nc,d\r"unclosed_to_chunk_e'  (30 bytes)
      #   gsub strips '"unclosed_to_chunk_e' → unquoted = "a,b\r\nc,d\r"
      #   quote count = 1 (odd) → in_quote = true
      #   trailing "\r" + in_quote branch: cr += 1   (line covered)
      #   counts after chunk1: crlf=1, cr=1 → no clear majority, continue.
      # chunk2 finds the close and counts 2× \r\n → crlf=3, cr=1.
      # Final: crlf(3) > lf+cr(0+1=1) → "\r\n"
      expect(guess(io, auto_row_sep_chars: 30)).to eq("\r\n")
    end
  end
end
