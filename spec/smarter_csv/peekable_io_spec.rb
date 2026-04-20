# frozen_string_literal: true

require 'spec_helper'
require 'stringio'

# IO-like with NO external_encoding — simulates custom wrappers, legacy adapters,
# decompression streams, etc. that don't expose an encoding. Returns ASCII-8BIT.
class NilEncodingIO
  def initialize(str)
    @io = StringIO.new(str.b)
  end

  def read(num_bytes = nil)
    @io.read(num_bytes)
  end

  def gets(sep = $/)
    @io.gets(sep)
  end

  def each_char(&block)
    @io.each_char(&block)
  end

  def eof?
    @io.eof?
  end

  def close
    nil
  end
  # Intentionally does NOT implement external_encoding
end

# IO-like that simulates a transcoded File handle (e.g. File.open('f', 'r:EUC-JP:UTF-8')).
# StringIO#set_encoding does not support transcoding pairs (internal_encoding stays nil),
# so we use this wrapper to properly report both external and internal encodings.
# read(n) returns raw bytes without transcoding, matching real IO#read(n) behaviour.
class TranscodedIO
  def initialize(raw_bytes, external, internal)
    @io  = StringIO.new(raw_bytes.b)
    @ext = Encoding.find(external)
    @int = Encoding.find(internal)
  end

  def read(num_bytes = nil)
    @io.read(num_bytes)
  end

  def gets(sep = $/)
    @io.gets(sep)
  end

  def each_char(&block)
    @io.each_char(&block)
  end

  def eof?
    @io.eof?
  end

  def close
    nil
  end

  def external_encoding
    @ext
  end

  def internal_encoding
    @int
  end
end

# IO-like that declares only an external encoding (no transcoding pair) and returns
# ASCII-8BIT bytes from #gets. Simulates wrapper objects (pipes, STDIN, decompression
# streams) where external_encoding is known but the source doesn't re-tag on read.
# Needed to exercise the frozen-exhausted single-encoding path (internal_encoding == nil)
# in PeekableIO#gets — TranscodedIO cannot cover it because it requires both encodings.
class SingleEncodingIO
  def initialize(raw_bytes, external)
    @io  = StringIO.new(raw_bytes.b)
    @ext = Encoding.find(external)
  end

  def read(num_bytes = nil)
    @io.read(num_bytes)
  end

  def gets(sep = $/)
    @io.gets(sep)
  end

  def eof?
    @io.eof?
  end

  def close
    nil
  end

  def external_encoding
    @ext
  end

  def internal_encoding
    nil
  end
end

RSpec.describe SmarterCSV::PeekableIO do
  let(:content) { "header1,header2\nval1,val2\nval3,val4\n" }
  let(:io)      { StringIO.new(content) }
  let(:opts)    { SmarterCSV::Reader::Options::DEFAULT_OPTIONS.dup }
  subject(:pio) { described_class.new(io, opts) }

  # ---------------------------------------------------------------------------
  # Buffer lifecycle
  # ---------------------------------------------------------------------------
  describe 'buffer lifecycle' do
    it 'peek_buf is nil before peek is called' do
      expect(pio.instance_variable_get(:@peek_buf)).to be_nil
    end

    it 'peek_buf is set after peek' do
      pio.peek(16_384)
      expect(pio.instance_variable_get(:@peek_buf)).not_to be_nil
    end

    it 'peek_buf remains set after buffer is fully drained (kept alive for rewind)' do
      pio.peek(16_384)
      pio.read
      expect(pio.instance_variable_get(:@peek_buf)).not_to be_nil
    end

    it 'peek_pos advances to bytesize when buffer is exhausted via gets' do
      pio.peek(16_384)
      pio.gets("\n") until pio.eof?
      buf = pio.instance_variable_get(:@peek_buf)
      pos = pio.instance_variable_get(:@peek_pos)
      expect(pos).to be >= buf.bytesize
    end
  end

  # ---------------------------------------------------------------------------
  # #peek
  # ---------------------------------------------------------------------------
  describe '#peek' do
    it 'returns the peeked bytes as a string' do
      result = pio.peek(10)
      expect(result).to eq(content[0, 10])
    end

    it 'does not lose any data on subsequent gets' do
      pio.peek(16_384)
      expect(pio.gets("\n")).to eq("header1,header2\n")
      expect(pio.gets("\n")).to eq("val1,val2\n")
      expect(pio.gets("\n")).to eq("val3,val4\n")
    end

    it 'replays a partial peek correctly when sep spans the buffer boundary' do
      pio.peek(7) # "header1" — does not include the newline
      expect(pio.gets("\n")).to eq("header1,header2\n")
    end

    # Issue 3 — peek is not idempotent: a second call re-reads @io, overwrites
    # @peek_buf, and silently drops the unconsumed bytes from the first peek.
    it 'is idempotent: second peek returns same bytes without reading more from @io' do
      first  = pio.peek(10)
      second = pio.peek(10)
      expect(second.b).to eq(first.b)
      # Buffer must still replay all original bytes — no data dropped
      expect(pio.gets("\n")).to eq("header1,header2\n")
    end
  end

  # ---------------------------------------------------------------------------
  # #gets / #readline
  # ---------------------------------------------------------------------------
  describe '#gets' do
    it 'replays all peeked bytes before reading from underlying IO' do
      pio.peek(16_384)
      lines = []
      lines << pio.gets("\n") until pio.eof?
      expect(lines).to eq(["header1,header2\n", "val1,val2\n", "val3,val4\n"])
    end

    it 'returns nil at EOF' do
      pio.peek(16_384)
      pio.read
      expect(pio.gets("\n")).to be_nil
    end
  end

  describe '#readline' do
    it 'returns the next line (same as gets)' do
      pio.peek(16_384)
      expect(pio.readline("\n")).to eq("header1,header2\n")
    end

    it 'raises EOFError at EOF (unlike gets which returns nil)' do
      pio.peek(16_384)
      pio.read # consume all content
      expect { pio.readline("\n") }.to raise_error(EOFError)
    end
  end

  # ---------------------------------------------------------------------------
  # #read
  # ---------------------------------------------------------------------------
  describe '#read' do
    it 'returns all content after a full peek' do
      pio.peek(16_384)
      expect(pio.read).to eq(content)
    end

    it 'returns all content without any peek' do
      expect(pio.read).to eq(content)
    end
  end

  # ---------------------------------------------------------------------------
  # #each_char
  # ---------------------------------------------------------------------------
  describe '#each_char' do
    it 'replays peeked bytes then continues from underlying IO' do
      pio.peek(8)
      chars = []
      pio.each_char { |c| chars << c }
      expect(chars.join).to eq(content)
    end

    it 'works without peek' do
      chars = []
      pio.each_char { |c| chars << c }
      expect(chars.join).to eq(content)
    end

    # Issue 2 — each_char used UTF-8 fallback instead of BINARY for nil-encoding sources.
    # Bytes >= 128 in the peek buffer would raise Encoding::InvalidByteSequenceError.
    it 'does not raise for nil-encoding source with bytes >= 128' do
      pio = described_class.new(NilEncodingIO.new("caf\xC3\xA9\n"), opts)
      pio.peek(4) # "caf\xC3" in buffer — \xC3 is >= 128
      chars = []
      expect { pio.each_char { |c| chars << c } }.not_to raise_error
      expect(chars.map(&:b).join).to eq("caf\xC3\xA9\n".b)
    end
  end

  # ---------------------------------------------------------------------------
  # #rewind_buffer
  # ---------------------------------------------------------------------------
  describe '#rewind_buffer' do
    it 'replays the buffer from the start (simulates rewind without touching underlying IO)' do
      pio.peek(16_384)
      pio.gets("\n") # consume first line
      pio.rewind_buffer
      expect(pio.gets("\n")).to eq("header1,header2\n") # replayed
    end

    it 'can be called multiple times' do
      pio.peek(16_384)
      3.times { pio.rewind_buffer }
      expect(pio.gets("\n")).to eq("header1,header2\n")
    end
  end

  # ---------------------------------------------------------------------------
  # #eof?
  # ---------------------------------------------------------------------------
  describe '#eof?' do
    it 'is false while peek buffer has unread bytes' do
      pio.peek(16_384)
      expect(pio.eof?).to be false
    end

    it 'is true after all content is consumed' do
      pio.peek(16_384)
      pio.read
      expect(pio.eof?).to be true
    end

    it 'is true on an empty source' do
      empty_pio = described_class.new(StringIO.new(''), opts)
      expect(empty_pio.eof?).to be true
    end
  end

  # ---------------------------------------------------------------------------
  # #external_encoding
  # ---------------------------------------------------------------------------
  describe '#external_encoding' do
    it 'delegates to the underlying IO' do
      enc_io = StringIO.new(content)
      enc_io.set_encoding(Encoding::ISO_8859_1)
      pio = described_class.new(enc_io, opts)
      expect(pio.external_encoding).to eq(Encoding::ISO_8859_1)
    end

    it 'returns nil when underlying IO does not respond to external_encoding' do
      bare = Object.new
      allow(bare).to receive(:respond_to?).with(:external_encoding).and_return(false)
      pio = described_class.new(bare, opts)
      expect(pio.external_encoding).to be_nil
    end
  end

  # ---------------------------------------------------------------------------
  # method_missing / respond_to_missing? — ALLOWED_METHODS allow-list contract
  #
  # PeekableIO is internal to SmarterCSV. reader.rb is the only caller, and the
  # only method it reaches through method_missing is #encoding (as a fallback in
  # the UTF-8 warning check). The allow-list codifies that contract:
  #
  #   * methods on ALLOWED_METHODS that @io implements → delegated
  #   * everything else → NoMethodError
  #
  # This raises loudly on a future maintainer's typo (fh.seek, fh.readpartial,
  # fh.some_new_io_method) instead of silently desyncing @peek_pos from @io.
  # Adding to ALLOWED_METHODS is a deliberate contract change.
  # ---------------------------------------------------------------------------
  describe '#method_missing' do
    it 'delegates allow-listed methods to the underlying IO' do
      sio = StringIO.new(content)
      # StringIO does not define :encoding natively, so stub it to prove delegation.
      allow(sio).to receive(:encoding).and_return(Encoding::ISO_8859_1)
      pio = described_class.new(sio, opts)
      expect(pio.encoding).to eq(Encoding::ISO_8859_1)
    end

    it 'raises NoMethodError for methods not on the allow-list even when @io implements them' do
      sio = StringIO.new(content)
      pio = described_class.new(sio, opts)
      # StringIO#string exists — it used to delegate through method_missing. The
      # allow-list narrows the contract: string is not a generic IO method, so
      # PeekableIO no longer exposes it. Intentional contract change.
      expect { pio.string }.to raise_error(NoMethodError)
    end

    it 'raises NoMethodError for position-changing methods that would desync the buffer' do
      sio = StringIO.new(content)
      pio = described_class.new(sio, opts)
      # These are the exact failure modes the allow-list protects against:
      # forwarding would advance @io past the peeked bytes while @peek_pos stays
      # behind, silently corrupting replay after rewind_buffer.
      expect { pio.seek(0) }.to raise_error(NoMethodError)
      expect { pio.pos = 0 }.to raise_error(NoMethodError)
      expect { pio.ungetc('x') }.to raise_error(NoMethodError)
    end

    # Known IO hazards — methods on @io that would either advance its read position
    # without updating @peek_pos, or bypass our encoding handling. Strictly speaking
    # the allow-list mechanism already protects against them (any non-allow-listed
    # method raises via the same code path), but enumerating them here:
    #   (a) documents in the spec which IO methods we deliberately block, and
    #   (b) fails loudly if any of them ever gets added to ALLOWED_METHODS by mistake.
    KNOWN_HAZARDOUS_METHODS = %i[
      seek pos= lineno=
      ungetc ungetbyte
      readpartial readbyte getbyte
      sysread sysseek
      readlines each_line each_byte
    ].freeze

    KNOWN_HAZARDOUS_METHODS.each do |m|
      it "raises NoMethodError when ##{m} is called (hazardous — would desync the buffer)" do
        sio = StringIO.new(content)
        pio = described_class.new(sio, opts)
        # @io's capabilities don't matter here: PeekableIO#method_missing short-circuits to `super`
        # for un-allow-listed methods before @io.respond_to? is consulted,
        # so these raise regardless of what @io implements.
        expect(pio.respond_to?(m)).to be false

        # Arity varies — use public_send with a harmless arg; the allow-list guard fires before args are inspected.
        # public_send (not send) is required: some hazardous names like #readlines are private Kernel methods
        # mixed into every object, and plain #send bypasses privacy, invoking Kernel's version instead of
        # reaching PeekableIO#method_missing. public_send matches how an external caller would invoke the API.
        expect do
                   pio.public_send(m, 0)
        rescue StandardError
                   pio.public_send(m)
        end.to raise_error(NoMethodError)
      end
    end
  end

  describe '#respond_to_missing?' do
    it 'returns true for allow-listed methods that @io implements' do
      sio = StringIO.new(content)
      allow(sio).to receive(:encoding).and_return(Encoding::UTF_8)
      pio = described_class.new(sio, opts)
      expect(pio.respond_to?(:encoding)).to be true
    end

    it 'returns false for methods not on the allow-list, even when @io implements them' do
      sio = StringIO.new(content)
      pio = described_class.new(sio, opts)
      # StringIO has #string and #seek; neither is on ALLOWED_METHODS.
      expect(pio.respond_to?(:string)).to be false
      expect(pio.respond_to?(:seek)).to be false
    end

    it 'returns false for allow-listed methods that @io does not implement' do
      # StringIO does not define :encoding. Being on the allow-list is necessary
      # but not sufficient — @io must also respond.
      sio = StringIO.new(content)
      pio = described_class.new(sio, opts)
      expect(pio.respond_to?(:encoding)).to be false
    end

    it 'returns false for methods neither PeekableIO nor the underlying IO respond to' do
      sio = StringIO.new(content)
      pio = described_class.new(sio, opts)
      expect(pio.respond_to?(:nonexistent_xyz)).to be false
    end
  end

  # ---------------------------------------------------------------------------
  # Multi-byte character spanning peek buffer boundary
  #
  # If peek(n) stops mid-codepoint, the buffer ends with an incomplete byte
  # sequence. Without alignment, gets passes the truncated bytes to the caller
  # and @io resumes at a continuation byte — which can corrupt output or raise
  # Encoding::InvalidByteSequenceError for encodings like Shift-JIS or EUC-JP
  # where a continuation byte can be re-interpreted as a new lead byte.
  #
  # The fix in peek reads extra bytes (one at a time) until the buffer ends on
  # a complete character boundary (valid_encoding? is true for the declared enc).
  # ---------------------------------------------------------------------------
  describe 'multi-byte character spanning peek buffer boundary' do
    # Build 2-line content: "hdr\n#{char}\n" encoded in the given encoding.
    # "hdr\n" is 4 bytes in UTF-8, Shift-JIS, and EUC-JP (all ASCII-safe).
    def multibyte_content(char_str, encoding)
      ("hdr\n" + char_str + "\n").encode(encoding)
    end

    # Peek at (4 + split_at) bytes to place the split split_at bytes into the
    # multi-byte char, then read all lines and return the concatenated raw bytes.
    def read_with_split(char_str, encoding, split_at)
      content = multibyte_content(char_str, encoding)
      io = StringIO.new(content)
      pio = described_class.new(io, opts)
      pio.peek(4 + split_at)
      lines = []
      lines << pio.gets("\n") until pio.eof?
      lines.map(&:b).join
    end

    # --- UTF-8: 2-byte, 3-byte, 4-byte codepoints at every possible split ---
    {
      'é  (U+00E9,  2-byte UTF-8)' => ['é', 'UTF-8', 2],
      '日  (U+65E5,  3-byte UTF-8)' => ['日', 'UTF-8', 3],
      '😀 (U+1F600, 4-byte UTF-8)' => ['😀', 'UTF-8', 4],
      '🎉 (U+1F389, 4-byte UTF-8)' => ['🎉', 'UTF-8', 4],
    }.each do |label, (char, enc, byte_size)|
      (1...byte_size).each do |split_at|
        it "#{label}: peek splits at byte #{split_at}/#{byte_size}" do
          expected = multibyte_content(char, enc).b
          expect(read_with_split(char, enc, split_at)).to eq(expected)
        end
      end
    end

    # --- Shift-JIS: 2-byte kanji (亜 = \x88\x9E) ---
    # The trail byte \x9E is itself a Shift-JIS lead byte, so @io.gets starting
    # there can re-interpret it as the start of a new 2-byte sequence and
    # swallow the following \n (0x0A is NOT a valid trail byte but behavior
    # depends on the Ruby runtime's error handling).
    it 'Shift_JIS 亜 (2-byte): peek splits at byte 1/2' do
      expected = multibyte_content('亜', 'Shift_JIS').b
      expect(read_with_split('亜', 'Shift_JIS', 1)).to eq(expected)
    end

    # --- EUC-JP: 2-byte kanji (日 = \xC6\xFC in EUC-JP) ---
    it 'EUC-JP 日 (2-byte): peek splits at byte 1/2' do
      expected = multibyte_content('日', 'EUC-JP').b
      expect(read_with_split('日', 'EUC-JP', 1)).to eq(expected)
    end

    # --- Larger UTF-8 grapheme clusters (split within the first codepoint) ---
    # These sequences are multiple codepoints that form a single visual character.
    # Our fix guarantees the buffer ends on a codepoint boundary; the ZWJ glue
    # bytes between codepoints are safely handled by the else branch of gets.
    [
      # 8 bytes: waving hand (U+1F44B, 4 bytes) + dark skin tone (U+1F3FF, 4 bytes)
      ['waving hand + dark skin tone modifier (8-byte grapheme cluster)', "👋🏿", 2],
      # 11 bytes: woman (4) + ZWJ (3) + heart (3) — split within first codepoint
      ['woman + ZWJ + heart (12-byte grapheme, split at byte 2)',         "👩‍❤️", 2],
      # 25+ bytes: family ZWJ sequence — split at byte 2 within the first codepoint
      ['family ZWJ emoji 👨‍👩‍👧‍👦 (25-byte grapheme, split at byte 2)', "👨‍👩‍👧‍👦", 2],
    ].each do |label, char, split_at|
      it "UTF-8 #{label}" do
        expected = multibyte_content(char, 'UTF-8').b
        expect(read_with_split(char, 'UTF-8', split_at)).to eq(expected)
      end
    end

    # --- IO.pipe sources with declared encoding (more realistic than StringIO) ---
    # IO.pipe is non-seekable and encoding-tagged; gets on a misaligned pipe can
    # raise or return garbage depending on the Ruby version and encoding.
    def pipe_with_split(char_str, encoding, split_at)
      raw = ("hdr\n" + char_str + "\n").encode(encoding).b
      reader, writer = IO.pipe(encoding)
      writer.write(raw)
      writer.close
      pio = described_class.new(reader, opts)
      pio.peek(4 + split_at)
      lines = []
      lines << pio.gets("\n") until pio.eof?
      lines.map(&:b).join
    ensure
      begin
        reader.close
      rescue StandardError
        nil
      end
    end

    it 'UTF-8 pipe: 😀 (4-byte) split at byte 2' do
      expected = multibyte_content('😀', 'UTF-8').b
      expect(pipe_with_split('😀', 'UTF-8', 2)).to eq(expected)
    end

    it 'Shift_JIS pipe: 亜 (2-byte) split at byte 1' do
      expected = multibyte_content('亜', 'Shift_JIS').b
      expect(pipe_with_split('亜', 'Shift_JIS', 1)).to eq(expected)
    end

    it 'EUC-JP pipe: 日 (2-byte) split at byte 1' do
      expected = multibyte_content('日', 'EUC-JP').b
      expect(pipe_with_split('日', 'EUC-JP', 1)).to eq(expected)
    end
  end

  # ---------------------------------------------------------------------------
  # Bug 1 — \r\n separator straddling the peek buffer boundary
  #
  # If peek(n) leaves \r as the last byte of @peek_buf, the \n that completes
  # the \r\n separator is the first byte of @io.  byteindex("\r\n") finds nothing
  # in the buffer, the else branch calls @io.gets("\r\n") which starts reading
  # at \n and returns "\ndata\r\n" — merging two lines into one returned string.
  # ---------------------------------------------------------------------------
  describe 'Bug 1 — \\r\\n separator straddling the peek buffer boundary' do
    it 'returns only the first line when \\r is the last buffer byte' do
      pio = described_class.new(StringIO.new("hdr\r\ndata\r\n"), opts)
      pio.peek(4) # "hdr\r" — \r last byte, \n is first byte of @io
      expect(pio.gets("\r\n")).to eq("hdr\r\n")
    end

    it 'does not merge two lines when \\r\\n straddles the boundary' do
      pio = described_class.new(StringIO.new("hdr\r\ndata\r\n"), opts)
      pio.peek(4)
      expect(pio.gets("\r\n")).to eq("hdr\r\n")
      expect(pio.gets("\r\n")).to eq("data\r\n")
    end

    it 'round-trips all lines when \\r\\n straddles the boundary' do
      content = "hdr\r\ndata\r\n"
      pio = described_class.new(StringIO.new(content), opts)
      pio.peek(4)
      lines = []
      lines << pio.gets("\r\n") until pio.eof?
      expect(lines.join).to eq(content)
    end

    it 'returns rest when buffer ends with sep prefix but @io is at EOF' do
      # "hdr\r" — \r looks like start of \r\n but nothing follows (EOF)
      pio = described_class.new(StringIO.new("hdr\r"), opts)
      pio.peek(4) # entire content in buffer, \r at end
      expect(pio.gets("\r\n").b).to eq("hdr\r".b)
    end

    it 'returns correct line when buffer ends with \\r but next byte is not \\n (standalone \\r in content)' do
      # "hdr\rdata\r\n" — the first \r is content, not part of the separator
      pio = described_class.new(StringIO.new("hdr\rdata\r\n"), opts)
      pio.peek(4) # "hdr\r" in buffer; "data\r\n" in @io
      expect(pio.gets("\r\n").b).to eq("hdr\rdata\r\n".b)
    end

    # Issue 1 — rewind after gets crosses the buffer boundary
    #
    # Before the fix, bytes fetched from @io during gets were returned to the caller
    # but never stored in @peek_buf. A rewind + re-read would produce wrong output
    # because those bytes were gone from @io but absent from the buffer.
    it 'rewind_buffer replays correctly after gets consumed bytes from @io (straddle case)' do
      pio = described_class.new(StringIO.new("hdr\r\ndata\r\n"), opts)
      pio.peek(4)                                    # "hdr\r" in buffer, "\ndata\r\n" in @io
      expect(pio.gets("\r\n")).to eq("hdr\r\n")      # triggers straddle: reads \n from @io
      pio.rewind_buffer
      expect(pio.gets("\r\n")).to eq("hdr\r\n")      # must return same line, not garbage
      expect(pio.gets("\r\n")).to eq("data\r\n")
    end

    it 'rewind_buffer replays correctly after gets consumed bytes from @io (normal boundary case)' do
      # peek(3) means sep "\n" is not in buffer "hdr"; gets must read from @io
      pio = described_class.new(StringIO.new("hdr\ndata\n"), opts)
      pio.peek(3)                                    # "hdr" in buffer, "\ndata\n" in @io
      expect(pio.gets("\n")).to eq("hdr\n")          # reads "\n" + "data\n" from @io
      pio.rewind_buffer
      expect(pio.gets("\n")).to eq("hdr\n")
      expect(pio.gets("\n")).to eq("data\n")
    end

    it 'rewind_buffer replays correctly after multiple gets calls each crossing the buffer boundary' do
      # peek(3) buffers "abc". Both gets calls must read from @io and accumulate into
      # @peek_buf (buffer not yet frozen). After rewind_buffer (@buffer_frozen = true) the
      # full replay must return both lines correctly.
      pio = described_class.new(StringIO.new("abcde\nfghij\nklmno\n"), opts)
      pio.peek(3)                                      # "abc" in buffer
      expect(pio.gets("\n")).to eq("abcde\n")          # extends buffer: "abc" + "de\n"
      expect(pio.gets("\n")).to eq("fghij\n")          # buffer exhausted: accumulates "fghij\n"
      pio.rewind_buffer
      expect(pio.gets("\n")).to eq("abcde\n")
      expect(pio.gets("\n")).to eq("fghij\n")
      expect(pio.gets("\n")).to eq("klmno\n")          # post-rewind: from @io directly
    end

    it 'rewind_buffer replays correctly after straddle-content path (\\r at boundary, next byte is not \\n)' do
      # buffer ends with \r, @io starts with "d" (not \n) — peeked bytes are content,
      # not a separator completion. Both peeked + remainder must be stored in @peek_buf.
      pio = described_class.new(StringIO.new("hdr\rdata\r\nfoo\r\n"), opts)
      pio.peek(4) # "hdr\r" in buffer; "data\r\nfoo\r\n" in @io
      expect(pio.gets("\r\n").b).to eq("hdr\rdata\r\n".b)
      pio.rewind_buffer
      expect(pio.gets("\r\n").b).to eq("hdr\rdata\r\n".b)
      expect(pio.gets("\r\n").b).to eq("foo\r\n".b)
    end
  end

  # ---------------------------------------------------------------------------
  # Bug 5 — frozen-phase straddle: \r at buffer boundary, \r\n starts @io
  #
  # The detection phase (unfrozen) handles this correctly: extend_buffer! absorbs
  # the boundary so the separator "\r\n" is always found within the buffer.
  #
  # The frozen phase is different: the straddle-detection branch reads one byte
  # ahead from @io (peeked = "\r"). Since "\r" != "\n" (tail_needed), the else
  # branch fires and calls @io.gets("\r\n") which starts reading from AFTER the
  # peeked "\r", at "\ndata\r\n". It returns "\ndata\r\n", so the combined
  # result is rest + "\r" + "\ndata\r\n" = "hdr\r\r\ndata\r\n" — two rows merged.
  #
  # Content layout: "hdr\r" (buffer, 4 bytes) | "\r\ndata\r\n" (@io)
  # Full content:   "hdr\r\r\ndata\r\n"
  # Correct lines:  "hdr\r\r\n", "data\r\n"
  # ---------------------------------------------------------------------------
  describe 'Bug 5 — frozen-phase straddle else-branch: content \\r at boundary, sep \\r\\n in @io' do
    it 'returns only the first line (currently FAILING — two rows are merged)' do
      pio = described_class.new(StringIO.new("hdr\r\r\ndata\r\n"), opts, buffer_size: 4)
      pio.peek           # fills buffer with exactly "hdr\r" (4 bytes)
      pio.freeze_buffer!
      pio.rewind_buffer
      expect(pio.gets("\r\n").b).to eq("hdr\r\r\n".b)
    end

    it 'returns both lines correctly (currently FAILING — second line is swallowed)' do
      pio = described_class.new(StringIO.new("hdr\r\r\ndata\r\n"), opts, buffer_size: 4)
      pio.peek
      pio.freeze_buffer!
      pio.rewind_buffer
      pio.gets("\r\n")   # consume first line (whatever it returns)
      expect(pio.gets("\r\n").b).to eq("data\r\n".b)
    end
  end

  # ---------------------------------------------------------------------------
  # Frozen-phase straddle: edge cases for lines 169, 189-190, 196-197
  # ---------------------------------------------------------------------------
  describe 'frozen-phase straddle: additional boundary cases' do
    # Line 169: buffer ends with \r (prefix of \r\n), but @io is at EOF.
    # peeked = @io.read(1) returns nil → combined = rest.b (no separator appended).
    it 'returns the final bytes when @io is at EOF during straddle peek (line 169)' do
      pio = described_class.new(StringIO.new("ab\r"), opts, buffer_size: 3)
      pio.peek
      pio.freeze_buffer!
      pio.rewind_buffer
      expect(pio.gets("\r\n").b).to eq("ab\r".b)
      expect(pio.gets("\r\n")).to be_nil
    end

    # Lines 189-190: buffer ends with \r, @io starts with \r (peeked), then \x (not \n).
    # Nested straddle check: peeked "\r" ends with sep prefix → confirmed_tail = "x" ≠ "\n"
    # → lines 189-190: remainder = @io.gets(sep), content = peeked + confirmed_tail + remainder
    it 'returns the correct line when peeked ends with sep prefix but confirmed_tail mismatches (lines 189-190)' do
      # buffer = "hdr\r", @io = "\rxmore\r\ndata\r\n"
      pio = described_class.new(StringIO.new("hdr\r\rxmore\r\ndata\r\n"), opts, buffer_size: 4)
      pio.peek
      pio.freeze_buffer!
      pio.rewind_buffer
      expect(pio.gets("\r\n").b).to eq("hdr\r\rxmore\r\n".b)
      expect(pio.gets("\r\n").b).to eq("data\r\n".b)
    end

    # Lines 196-197: buffer ends with \r, @io starts with a byte that is NOT a sep prefix.
    # Nested straddle check: peeked "x" does not end with "\r" → nested_handled = false
    # → lines 196-197: remainder = @io.gets(sep), content = peeked + remainder
    it 'returns the correct line when peeked does not end with any sep prefix (lines 196-197)' do
      # buffer = "hdr\r", @io = "xmore\r\ndata\r\n"
      pio = described_class.new(StringIO.new("hdr\rxmore\r\ndata\r\n"), opts, buffer_size: 4)
      pio.peek
      pio.freeze_buffer!
      pio.rewind_buffer
      expect(pio.gets("\r\n").b).to eq("hdr\rxmore\r\n".b)
      expect(pio.gets("\r\n").b).to eq("data\r\n".b)
    end
  end

  # ---------------------------------------------------------------------------
  # Bug 2 — read(n) returns fewer bytes than requested when n spans buffer + @io
  #
  # When n > buffered.bytesize, buffered[0, n] returns only the buffer portion.
  # The remaining (n - buffered.bytesize) bytes that sit in @io are never read,
  # violating Ruby's IO#read(n) contract.
  # ---------------------------------------------------------------------------
  describe 'Bug 2 — read(n) spanning peek buffer and underlying IO' do
    it 'returns exactly n bytes when n exceeds the buffered portion' do
      pio = described_class.new(StringIO.new("abcdefghij"), opts)
      pio.peek(3)          # "abc" in buffer, "defghij" in @io
      expect(pio.read(7).b).to eq("abcdefg".b)
    end

    it 'returns all available bytes when n exceeds total content length' do
      pio = described_class.new(StringIO.new("abcde"), opts)
      pio.peek(3)          # "abc" in buffer, "de" in @io
      expect(pio.read(100).b).to eq("abcde".b)
    end

    it 'returns exactly n bytes from the buffer alone when n <= buffered size' do
      pio = described_class.new(StringIO.new("abcdefg"), opts)
      pio.peek(7)          # all 7 bytes buffered
      expect(pio.read(3).b).to eq("abc".b)
    end

    it 'read(0) returns empty string and does not advance peek_pos' do
      pio = described_class.new(StringIO.new("abcdefg"), opts)
      pio.peek(7)
      pos_before = pio.instance_variable_get(:@peek_pos)
      result = pio.read(0)
      expect(result.b).to eq(''.b)
      expect(pio.instance_variable_get(:@peek_pos)).to eq(pos_before)
    end
  end

  # ---------------------------------------------------------------------------
  # read(n) in the frozen phase
  #
  # Bug 2 tests cover unfrozen reads.  These tests verify that read(n) works
  # correctly after freeze_buffer! + rewind_buffer — the normal processing path.
  # ---------------------------------------------------------------------------
  describe 'read(n) in the frozen phase' do
    it 'returns exactly n bytes when n spans the peek buffer and @io' do
      pio = described_class.new(StringIO.new("abcdefghij"), opts, buffer_size: 3)
      pio.peek # "abc" in buffer, "defghij" in @io
      pio.freeze_buffer!
      pio.rewind_buffer
      expect(pio.read(5).b).to eq("abcde".b)  # 3 from buffer + 2 from @io
      expect(pio.read(5).b).to eq("fghij".b)  # all from @io
    end

    it 'returns all remaining bytes when n exceeds total content (frozen)' do
      pio = described_class.new(StringIO.new("abcde"), opts, buffer_size: 3)
      pio.peek           # "abc" in buffer, "de" in @io
      pio.freeze_buffer!
      pio.rewind_buffer
      expect(pio.read(100).b).to eq("abcde".b)
    end

    it 'returns nil when called after all content is consumed (frozen)' do
      pio = described_class.new(StringIO.new("abc"), opts, buffer_size: 3)
      pio.peek
      pio.freeze_buffer!
      pio.rewind_buffer
      pio.read(3)
      expect(pio.read(1)).to be_nil
    end

    it 'returns entire content via read(nil) in the frozen phase' do
      pio = described_class.new(StringIO.new("abcdefghij"), opts, buffer_size: 4)
      pio.peek           # "abcd" in buffer, "efghij" in @io
      pio.freeze_buffer!
      pio.rewind_buffer
      expect(pio.read.b).to eq("abcdefghij".b)
    end
  end

  # ---------------------------------------------------------------------------
  # Issue 4 — align_to_char_boundary unbounded loop on malformed input
  #
  # A corrupt byte anywhere in the first peek chunk makes valid_encoding? permanently
  # false.  Without a cap the loop would drain the entire file one byte at a time.
  # MAX_ALIGN_BYTES = 4 limits attempts to the longest codepoint in any Ruby-supported
  # variable-width encoding, so the loop always terminates quickly.
  # ---------------------------------------------------------------------------
  describe 'Issue 4 — align_to_char_boundary stops after MAX_ALIGN_BYTES on malformed input' do
    it 'does not drain @io when the buffer contains an invalid byte sequence' do
      # \xFF is never valid in UTF-8; valid_encoding? stays false no matter how many
      # extra bytes are appended.  After MAX_ALIGN_BYTES attempts @io must still have
      # the remaining data intact — the loop must not have consumed it all.
      bad_utf8  = "\xFF".b                          # permanently invalid in UTF-8
      rest      = ("a" * 100).b                     # 100 good bytes still in @io
      sio = StringIO.new((bad_utf8 + rest).force_encoding('UTF-8'))
      pio = described_class.new(sio, opts)
      pio.peek(1) # peeks just the \xFF byte; triggers align_to_char_boundary
      # After peek, @io must still have most of its data — the loop read at most 4 bytes
      remaining = sio.read
      expect(remaining.bytesize).to be >= (rest.bytesize - SmarterCSV::PeekableIO::MAX_ALIGN_BYTES)
    end
  end

  # ---------------------------------------------------------------------------
  # Bug 3 — peek return value diverges from @peek_buf after char-boundary alignment
  #
  # align_to_char_boundary may read extra bytes from @io and stores them in
  # @peek_buf, but peek still returns the original chunk (before alignment).
  # The return value therefore no longer matches what was actually buffered.
  # ---------------------------------------------------------------------------
  describe 'Bug 3 — peek return value after char-boundary alignment' do
    it 'returns all buffered bytes including the alignment bytes' do
      # "ab" (2 bytes) + 😀 (U+1F600, 4 bytes) = 6 bytes total
      # peek(3) reads "ab\xF0"; align_to_char_boundary extends to "ab😀" (6 bytes)
      content = "ab\u{1F600}"
      pio = described_class.new(StringIO.new(content), opts)
      returned = pio.peek(3)
      expect(returned.b).to eq(content.b)
    end
  end

  # ---------------------------------------------------------------------------
  # Issue 3 — transcoding path raises Encoding::InvalidByteSequenceError when peek
  # boundary splits a multi-byte codepoint in the external encoding
  #
  # When a file is opened with a transcoding pair (e.g. r:euc-jp:utf-8), read(n)
  # returns raw external-encoding bytes without transcoding.  If byte n falls in the
  # middle of a 2- or 3-byte EUC-JP character, calling encode('UTF-8') on the raw
  # bytes raises Encoding::InvalidByteSequenceError before align_to_char_boundary
  # is ever reached.  The fix retries with one more raw byte up to MAX_ALIGN_BYTES.
  # ---------------------------------------------------------------------------
  describe 'Issue 3 — transcoding path handles peek boundary mid-codepoint' do
    # EUC-JP "日" = \xC6\xFC (2 bytes).  We peek only the first byte (\xC6) so that
    # encode('UTF-8') would raise without the fix.
    let(:euc_jp_hi) { "\xC6".b }         # first byte of EUC-JP "日" (\xC6\xFC)
    let(:euc_jp_lo) { "\xFC".b }         # second byte
    let(:rest)      { ",data\n".b }

    def transcoded_io(raw_bytes)
      TranscodedIO.new(raw_bytes, 'EUC-JP', 'UTF-8')
    end

    it 'does not raise when peek splits a 2-byte EUC-JP codepoint' do
      io = transcoded_io(euc_jp_hi + euc_jp_lo + rest)
      pio = described_class.new(io, opts)
      expect { pio.peek(1) }.not_to raise_error # peek(1) reads only \xC6
    end

    it 'returns raw external-encoding bytes aligned to a complete codepoint' do
      io = transcoded_io(euc_jp_hi + euc_jp_lo + rest)
      pio = described_class.new(io, opts)
      result = pio.peek(1)
      # peek returns raw bytes in the external encoding — transcoding to internal
      # happens on read-out (gets/read/each_char), not during storage.
      expect(result.encoding).to eq(Encoding.find('EUC-JP'))
      expect(result.valid_encoding?).to be true
    end

    it 'replays all content correctly after peek + rewind_buffer' do
      io = transcoded_io(euc_jp_hi + euc_jp_lo + rest)
      pio = described_class.new(io, opts)
      pio.peek(1)
      pio.rewind_buffer
      full = pio.read
      expect(full.encoding).to eq(Encoding::UTF_8) # maybe_transcode applies ext→int on read-out
      expect(full.valid_encoding?).to be true
      expect(full.b.bytesize).to be > 0
    end

    it 'does not raise when EOF is hit while reading alignment bytes (truncated codepoint at end of stream)' do
      # Stream contains only the first byte of a 2-byte EUC-JP character — EOF mid-codepoint.
      # peek(1) reads \xC6; retry loop calls @io.read(1) → nil (EOF); `break unless extra` fires.
      # transcoded is still nil → falls through to encode(invalid: :replace).
      io = transcoded_io(euc_jp_hi) # only \xC6, no \xFC — stream ends immediately
      pio = described_class.new(io, opts)
      expect { pio.peek(1) }.not_to raise_error
    end

    it 'exhausts MAX_ALIGN_BYTES attempts then falls back to replacement without consuming extra bytes' do
      # peek(1) reads one \xFF (invalid EUC-JP lead byte).
      # The retry loop reads exactly MAX_ALIGN_BYTES more \xFF bytes one at a time — encode
      # keeps raising after each addition. After MAX_ALIGN_BYTES iterations the loop exits
      # and encode(invalid: :replace) is used.
      # We supply 1 + MAX_ALIGN_BYTES + 1 bytes so the final byte remains in @io after the
      # loop — proving the loop stopped at MAX_ALIGN_BYTES and did not read one byte too many.
      n       = SmarterCSV::PeekableIO::MAX_ALIGN_BYTES
      garbage = ("\xFF" * (1 + n + 1)).b # \xFF is never valid in EUC-JP
      io      = TranscodedIO.new(garbage, 'EUC-JP', 'UTF-8')
      pio     = described_class.new(io, opts)
      expect { pio.peek(1) }.not_to raise_error
      expect(pio.peek.encoding).to eq(Encoding.find('EUC-JP')) # peek returns raw external-encoding bytes
      expect(io.read(1)).not_to be_nil # exactly 1 byte left — loop stopped at n
    end
  end

  # ---------------------------------------------------------------------------
  # Bug 4 — Encoding::CompatibilityError in gets else-branch for nil-encoding IO
  #
  # When the underlying IO has no external_encoding, @emit_encoding is nil and
  # rest is force-encoded as UTF-8 (the final fallback).  @io.gets returns an
  # ASCII-8BIT string.  Ruby's String#+ raises Encoding::CompatibilityError when
  # BOTH sides are non-ASCII-only — i.e. when the peek buffer itself contains
  # bytes ≥ 128 AND the remainder from @io also contains bytes ≥ 128.
  #
  # Minimal trigger: peek(3) fills the buffer with "é," (0xC3 0xA9 0x2C),
  # which is non-ASCII-only once force-encoded as UTF-8. @io.gets then returns
  # "世\r\n" (0xE4 0xB8 0x96 0x0D 0x0A) as ASCII-8BIT, also non-ASCII-only.
  # Concatenation: UTF-8(non-ASCII) + ASCII-8BIT(non-ASCII) → CompatibilityError.
  # ---------------------------------------------------------------------------
  describe 'Bug 4 — gets else-branch encoding mismatch for nil-encoding IO' do
    # "é,世\r\nAlice\r\n" — buffer gets "é," (3 bytes, non-ASCII), @io starts at "世"
    let(:bug4_content) { "é,世\r\nAlice\r\n" } # é=\xC3\xA9, 世=\xE4\xB8\x96

    it 'does not raise when both buffer and @io remainder contain bytes >= 128' do
      pio = described_class.new(NilEncodingIO.new(bug4_content), opts)
      pio.peek(3) # "é," (0xC3 0xA9 0x2C) buffered; "世\r\n..." in @io
      expect { pio.gets("\r\n") }.not_to raise_error
    end

    it 'returns the complete line when both buffer and @io remainder contain bytes >= 128' do
      pio = described_class.new(NilEncodingIO.new(bug4_content), opts)
      pio.peek(3)
      line = begin; pio.gets("\r\n"); rescue Encoding::CompatibilityError; nil; end
      expect(line&.b).to eq("é,世\r\n".b)
    end
  end

  # ---------------------------------------------------------------------------
  # Issue 5 — gets encoding inconsistency between the sep-found and sep-not-found paths
  #
  # Before the fix, rest was force-encoded as (@emit_encoding || external_encoding || UTF-8).
  # The "if idx" branch returned a string in that encoding (UTF-8 fallback for nil-encoding
  # sources), while the "else" branch used out_enc = (@emit_encoding || external_encoding)
  # with no UTF-8 fallback, returning BINARY.  Two consecutive gets calls on the same
  # nil-encoding source could return strings with different encodings depending solely on
  # whether the separator happened to land inside or outside the peek buffer.
  # ---------------------------------------------------------------------------
  describe 'Issue 5 — gets encoding consistency across sep-in-buffer and sep-in-IO paths' do
    it 'returns the same encoding whether sep is found in the buffer or in @io' do
      # peek(5) on "a,b\nc,d\n" buffers "a,b\nc"; first \n is in buffer, second is in @io.
      pio = described_class.new(NilEncodingIO.new("a,b\nc,d\n"), opts)
      pio.peek(5)
      line1 = pio.gets("\n")   # sep found in buffer (if-idx path)
      line2 = pio.gets("\n")   # sep found in @io    (else path)
      expect(line1.encoding).to eq(line2.encoding)
    end
  end

  # ---------------------------------------------------------------------------
  # c1 — each_char and read accumulate @io bytes into @peek_buf during detection
  #
  # When @buffer_frozen = false (before first rewind), every byte read from @io
  # must be appended to @peek_buf so that a subsequent rewind can replay the full
  # stream from position 0.  The bug: each_char delegated directly to @io.each_char
  # without accumulating, and read did not append @io bytes to @peek_buf.
  # ---------------------------------------------------------------------------
  describe 'c1 — each_char and read accumulate @io bytes into @peek_buf for rewind_buffer' do
    it 'each_char accumulates @io bytes so rewind_buffer can replay the full stream' do
      pio = described_class.new(StringIO.new("abcde\nfghij\n"), opts)
      pio.peek(4)  # buffer = "abcd" only; "e\nfghij\n" is still in @io
      chars = []
      pio.each_char { |c| chars << c }
      expect(chars.join).to eq("abcde\nfghij\n")
      pio.rewind_buffer
      expect(pio.gets("\n")).to eq("abcde\n")
      expect(pio.gets("\n")).to eq("fghij\n")
    end

    it 'read (no n) accumulates @io bytes so rewind_buffer can replay the full stream' do
      pio = described_class.new(StringIO.new("abcde\nfghij\n"), opts)
      pio.peek(4)  # buffer = "abcd" only; "e\nfghij\n" is still in @io
      result = pio.read
      expect(result).to eq("abcde\nfghij\n")
      pio.rewind_buffer
      expect(pio.read).to eq("abcde\nfghij\n")
    end
  end

  # ---------------------------------------------------------------------------
  # c2 — maybe_transcode replaces invalid/corrupt bytes instead of raising
  #
  # maybe_transcode calls encode(int) without invalid: :replace, so a malformed
  # byte sequence in the buffer raises Encoding::InvalidByteSequenceError.
  # The fix: add invalid: :replace, undef: :replace to mirror enforce_utf8_encoding.
  # ---------------------------------------------------------------------------
  describe 'c2 — maybe_transcode with invalid/corrupt bytes in buffer' do
    it 'replaces invalid bytes rather than raising' do
      # \xFF is not a valid EUC-JP byte sequence
      csv = "ok\xFF\nrest\n".b
      io  = TranscodedIO.new(csv, 'EUC-JP', 'UTF-8')
      pio = described_class.new(io, opts)
      pio.peek(10)
      expect { pio.gets("\n") }.not_to raise_error
    end

    it 'returns a UTF-8 string after replacing the invalid byte' do
      csv = "ok\xFF\nrest\n".b
      io  = TranscodedIO.new(csv, 'EUC-JP', 'UTF-8')
      pio = described_class.new(io, opts)
      pio.peek(10)
      line = pio.gets("\n")
      expect(line.encoding).to eq(Encoding::UTF_8)
      expect(line.valid_encoding?).to be true
    end
  end

  # ---------------------------------------------------------------------------
  # c3 — "buffer exhausted, not frozen" path in gets applies maybe_transcode
  #
  # When @buffer_frozen = false and @peek_pos >= @peek_buf.bytesize, gets reads
  # from @io and appends to @peek_buf.  The returned value was only force_encoding'd
  # without calling maybe_transcode, so transcoding pairs (ext→int) were silently
  # skipped and the caller received a string with the wrong encoding.
  # ---------------------------------------------------------------------------
  describe 'c3 — gets: buffer exhausted, not frozen, transcoding pair gets maybe_transcode' do
    it 'returns a correctly transcoded string when @io.gets is called during detection phase' do
      # \xfc = ü in ISO-8859-1
      csv = "line1\nM\xFCnchen\n".b
      io  = TranscodedIO.new(csv, 'ISO-8859-1', 'UTF-8')
      pio = described_class.new(io, opts)
      pio.peek(3) # buffer = "lin" only; "e1\n..." is still in @io
      pio.gets("\n") # reads "e1\n" from @io, appends to buf; not yet frozen
      line2 = pio.gets("\n") # buffer still exhausted+not frozen: reads "München\n" from @io
      expect(line2.encoding).to eq(Encoding::UTF_8)
      expect(line2).to eq("München\n")
    end

    it 'rewind_buffer replays the correctly transcoded content after buffer-exhausted reads' do
      csv = "line1\nM\xFCnchen\n".b
      io  = TranscodedIO.new(csv, 'ISO-8859-1', 'UTF-8')
      pio = described_class.new(io, opts)
      pio.peek(3)
      pio.gets("\n")
      pio.gets("\n")
      pio.rewind_buffer
      expect(pio.gets("\n")).to eq("line1\n")
      expect(pio.gets("\n")).to eq("München\n")
    end
  end

  describe 'guard clauses' do
    let(:opts) { {row_sep: "\n"} }

    it 'raises ArgumentError when gets is called with nil separator' do
      io = StringIO.new("a,b\n1,2\n")
      pio = described_class.new(io, opts)
      pio.peek
      expect { pio.gets(nil) }.to raise_error(ArgumentError, /does not support gets\(nil\)/)
    end

    it 'raises NoMethodError when rewind is called instead of rewind_buffer' do
      io = StringIO.new("a,b\n1,2\n")
      pio = described_class.new(io, opts)
      pio.peek
      expect { pio.rewind }.to raise_error(NoMethodError, /use rewind_buffer instead/)
    end
  end

  # ---------------------------------------------------------------------------
  # #gets without #peek — direct delegation to @io
  #
  # When the caller never calls #peek (auto-detection was skipped because both
  # separators were explicit), @peek_buf is nil and gets must delegate directly
  # to @io.gets(sep) without touching buffer state. This path is exercised
  # implicitly by integration tests that pass explicit separators, but was not
  # covered by a targeted unit test.
  # ---------------------------------------------------------------------------
  describe '#gets without #peek (direct @io delegation)' do
    let(:opts) { {row_sep: "\n"} }

    it 'returns the next line when peek was never called' do
      pio = described_class.new(StringIO.new("alpha\nbeta\n"), opts)
      expect(pio.gets("\n")).to eq("alpha\n")
    end

    it 'can be called repeatedly to read all lines in order' do
      pio = described_class.new(StringIO.new("a\nb\nc\n"), opts)
      expect(pio.gets("\n")).to eq("a\n")
      expect(pio.gets("\n")).to eq("b\n")
      expect(pio.gets("\n")).to eq("c\n")
    end

    it 'returns nil at EOF without ever filling the peek buffer' do
      pio = described_class.new(StringIO.new("only\n"), opts)
      expect(pio.gets("\n")).to eq("only\n")
      expect(pio.gets("\n")).to be_nil
      expect(pio.instance_variable_get(:@peek_buf)).to be_nil # confirms direct-delegation path
    end

    it 'applies the nil-separator guard even before the @peek_buf.nil? delegation check' do
      pio = described_class.new(StringIO.new("a\n"), opts)
      # Guard fires at method entry; must still raise even when @peek_buf is nil.
      expect { pio.gets(nil) }.to raise_error(ArgumentError, /does not support gets\(nil\)/)
    end
  end

  # ---------------------------------------------------------------------------
  # Frozen-phase delegation inconsistency between #gets and #read / #each_char
  #
  # #gets applies maybe_transcode on the frozen-exhausted path (peekable_io.rb:96-109),
  # so a wrapper IO that declares an ext:int encoding pair but does not transcode
  # on read (e.g. TranscodedIO) yields strings correctly tagged in the internal
  # encoding. #read and #each_char instead early-return @io.read(n) / @io.each_char
  # without re-tagging or transcoding. SmarterCSV's CSV pipeline only uses #gets,
  # so this inconsistency does not affect CSV parsing — but it is visible to any
  # external caller that uses PeekableIO as a general IO wrapper.
  #
  # These tests lock down the CURRENT behavior: #gets transcodes, #read and
  # #each_char do not. If we later decide to unify the paths, the #read and
  # #each_char assertions here will flag the behavior change.
  # ---------------------------------------------------------------------------
  describe 'frozen-phase delegation — #gets vs #read / #each_char encoding consistency' do
    # "hdr\n" + "foo\xE9bar\n" = 12 bytes; \xE9 is é in ISO-8859-1.
    # buffer_size: 4 puts only "hdr\n" in the initial peek, so after freeze_buffer!
    # + rewind_buffer + draining the 4-byte buffer, the next read/each_char/gets
    # hits the frozen-exhausted path.
    let(:raw) { "hdr\nfoo\xE9bar\n".b }
    let(:transcoding_io) { TranscodedIO.new(raw, 'ISO-8859-1', 'UTF-8') }

    def drained_frozen_pio(io)
      pio = described_class.new(io, {row_sep: "\n"}, buffer_size: 4)
      pio.peek
      pio.freeze_buffer!
      pio.rewind_buffer
      buffered_size = pio.instance_variable_get(:@peek_buf).bytesize
      pio.read(buffered_size) # drain the peek buffer exactly; next op hits @io
      pio
    end

    it '#gets applies maybe_transcode — returned line is tagged as internal encoding (UTF-8)' do
      pio = described_class.new(transcoding_io, {row_sep: "\n"}, buffer_size: 4)
      pio.peek
      pio.freeze_buffer!
      pio.rewind_buffer
      _first = pio.gets("\n")           # consumes buffer
      second = pio.gets("\n")           # hits frozen-exhausted path → delegates to @io + maybe_transcode
      expect(second.encoding).to eq(Encoding::UTF_8)
      expect(second.valid_encoding?).to be true
      expect(second).to eq("fooébar\n") # ISO-8859-1 \xE9 → UTF-8 é
    end

    it '#read does NOT apply maybe_transcode on the frozen-exhausted path (current behavior)' do
      pio = drained_frozen_pio(transcoding_io)
      extra = pio.read(5)
      # @io.read(n) on a non-transcoding wrapper returns ASCII-8BIT bytes.
      # PeekableIO#read delegates unchanged — no force_encoding, no maybe_transcode.
      expect(extra.encoding).to eq(Encoding::ASCII_8BIT)
      expect(extra.b).to eq("foo\xE9b".b)
    end

    it '#each_char does NOT apply maybe_transcode on the frozen-exhausted path (current behavior)' do
      pio = drained_frozen_pio(transcoding_io)
      chars = []
      pio.each_char { |c| chars << c }
      # @io.each_char on a StringIO containing .b bytes yields ASCII-8BIT chars.
      expect(chars.map(&:encoding).uniq).to eq([Encoding::ASCII_8BIT])
      expect(chars.join.b).to eq("foo\xE9bar\n".b)
    end
  end

  # ---------------------------------------------------------------------------
  # Frozen-exhausted path, single-encoding case (internal_encoding == nil)
  #
  # Covers peekable_io.rb:107-108 — the force_encoding step that tags the line
  # in the external encoding when there is no transcoding pair.
  #
  # Scenario: source declares external_encoding = ISO-8859-1 but returns
  # ASCII-8BIT bytes from #gets (EncodedBytesIO-style wrapper: pipes, STDIN,
  # decompression streams). With internal_encoding = nil, maybe_transcode is a
  # no-op — so the force_encoding call in gets is the only thing that tags the
  # returned line. Without it, reader.rb's enforce_utf8_encoding would interpret
  # the bytes as UTF-8 and replace every non-ASCII byte.
  # ---------------------------------------------------------------------------
  describe 'frozen-exhausted single-encoding path — #gets tags line in external encoding' do
    # "hdr\n" + "foo\xE9bar\n" = 12 bytes; \xE9 is é in ISO-8859-1.
    # buffer_size: 4 stops the initial peek at "hdr\n" so the next gets after
    # freeze_buffer! + rewind_buffer + draining hits the frozen-exhausted branch.
    let(:raw) { "hdr\nfoo\xE9bar\n".b }
    let(:single_enc_io) { SingleEncodingIO.new(raw, 'ISO-8859-1') }

    it '#gets returns a line tagged as the external encoding (ISO-8859-1) on the frozen-exhausted path' do
      pio = described_class.new(single_enc_io, {row_sep: "\n"}, buffer_size: 4)
      pio.peek
      pio.freeze_buffer!
      pio.rewind_buffer
      _first = pio.gets("\n")           # drains the 4-byte buffer
      second = pio.gets("\n")           # frozen-exhausted path: delegates to @io.gets
      expect(second.encoding).to eq(Encoding::ISO_8859_1)
      expect(second.b).to eq("foo\xE9bar\n".b) # bytes unchanged, only tag differs
    end
  end
end
