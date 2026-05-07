# frozen_string_literal: true

module SmarterCSV
  # PeekableIO wraps any IO-like object and buffers the first chunk of bytes
  # so that auto-detection (row_sep, col_sep) can call rewind without requiring
  # the underlying source to be seekable.
  #
  # Works transparently with files, StringIO, pipes, STDIN, Zlib streams, and
  # any other IO-like object that responds to read.
  #
  # Lifecycle:
  #   1. peek(n)     — reads up to n bytes from the underlying IO into the buffer
  #   2. rewind      — resets @peek_pos to 0 (replays buffer, never seeks underlying IO)
  #   3. gets/read/each_char — drain the buffer first, then read from @io in
  #      @buffer_size chunks, appending each to @peek_buf so that a subsequent
  #      rewind can replay the full stream from position 0.
  #   4. rewind — resets @peek_pos to 0; does NOT freeze. Detection may rewind
  #      multiple times (once per pass) and must keep accumulating between passes.
  #   5. freeze_buffer! — called once after all detection passes are done. After
  #      this point reads beyond the buffer delegate directly to @io without growing
  #      @peek_buf. @peek_buf is kept alive (never nilled) so rewind can replay.
  #
  class PeekableIO
    # 16KB is enough for separator detection on any real-world CSV header.
    # Matches one EBS gp3 I/O block and one Apple Silicon VM page exactly.
    DEFAULT_PEEK_SIZE = 16_384

    # Lower bound for a sane peek buffer chunk size. Below this the buffer is
    # too small to be useful even on local SSD (one VM page on x86 is 4 KB).
    MIN_BUFFER_SIZE = 4_096

    # Upper bound for the peek buffer chunk size. Equal to
    # AutoDetection::MAX_AUTO_ROW_SEP_CHARS — beyond this, bytes are unused by
    # auto-detection and only delay parse start by pre-loading bytes that
    # would have been read during parsing anyway.
    MAX_BUFFER_SIZE = SmarterCSV::AutoDetection::MAX_AUTO_ROW_SEP_CHARS

    def initialize(io, options, buffer_size: DEFAULT_PEEK_SIZE)
      @io = io
      @buffer_size = buffer_size
      @options = options  # live reference — options[:row_sep] is the default sep for gets/readline
      @peek_buf = nil     # nil = buffer not yet filled
      @peek_pos = 0
      @emit_encoding = nil # encoding of strings returned by @io.read — set on first peek
      @buffer_frozen = false # true after freeze_buffer!: buffer stops growing, detection phase is over
    end

    # Read up to n bytes into the buffer and return them.
    # Called once before auto-detection begins.
    #
    # Works for any IO source — files, StringIO, pipes, Zlib streams, etc.
    # The BOM (if any) is stripped immediately so all downstream code is clean.
    # For transcoded streams (e.g. r:iso-8859-1:utf-8), the raw bytes are
    # converted to the internal encoding in-place; @emit_encoding records the
    # final encoding so read-out can re-tag strings correctly.
    def peek(n = @buffer_size)
      # Idempotent: a second peek call returns the existing buffer without reading
      # more from @io.  Calling peek twice would otherwise overwrite the buffer and
      # silently drop any unconsumed bytes from the first peek.
      return @peek_buf.dup.force_encoding(@emit_encoding || Encoding::ASCII_8BIT) if @peek_buf

      # read(n) fetches raw bytes as ASCII-8BIT regardless of the file's declared
      # encoding — this is what we want because it works even for files that begin
      # with non-UTF-8 BOMs (\xFF\xFE etc.) that would cause gets(nil,n) on a
      # r:utf-8 handle to stop after the first invalid byte.
      chunk = @io.read(n)
      if chunk && !chunk.empty?
        raw = strip_bom(chunk.b)
        # The buffer always holds raw bytes in the external encoding (ASCII-8BIT tagged).
        # Transcoding (ext → int) is the caller's responsibility — it happens externally
        # when consuming data, not here during storage.
        @emit_encoding = external_encoding
        # Ensure the buffer ends on a complete codepoint boundary.
        # align_to_char_boundary reads single bytes from @io until the buffer is valid
        # in @emit_encoding, guarded by MAX_ALIGN_BYTES to avoid infinite loops on
        # malformed input. Skipped when encoding is unknown (nil) or single-byte.
        raw = align_to_char_boundary(raw) if @emit_encoding
        @peek_buf = raw
        @peek_pos = 0
      end
      # Return the full buffered content (BOM-stripped + char-aligned) rather than
      # the original chunk so callers see what was actually consumed.
      @peek_buf ? @peek_buf.dup.force_encoding(@emit_encoding || Encoding::ASCII_8BIT) : chunk
    end

    # Returns the next line up to and including sep.
    # Hot path: @peek_buf is nil (never peeked) or exhausted — delegate directly to @io.
    # The buffer is never nilled out by read methods so that rewind always works during
    # the auto-detection phase. @peek_pos advancing past bytesize is the exhaustion signal.
    #
    # NOTE: sep must be a String. gets(nil) — which reads until EOF in Ruby IO — is not
    # supported; smarter_csv always passes an explicit row separator string.
    # The default is @options[:row_sep] (resolved after auto-detection), never $/.
    #
    # NOTE: we don't support **kwargs because smarter_csv does not use them.
    #
    # NOTE: the limit parameter (Ruby IO#gets(sep, limit)) is intentionally omitted.
    # PeekableIO is internal to SmarterCSV and no caller passes a limit. If this class
    # were ever extracted into a stand-alone library, limit support would be required
    # to fully comply with the IO#gets contract.
    def gets(sep = @options[:row_sep])
      raise ArgumentError, "PeekableIO#gets does not support gets(nil) — pass an explicit separator string" if sep.nil?
      return @io.gets(sep) if @peek_buf.nil?

      # Buffer frozen (post auto-detection): delegate once buffer is exhausted — no more accumulation.
      # Must still apply encoding tagging and maybe_transcode so callers see consistent encodings.
      if @buffer_frozen && buffer_exhausted?
        line = @io.gets(sep)
        return nil if line.nil?

        int = internal_encoding
        # Real IO objects opened with a transcoding pair (e.g. r:iso-8859-1:utf-8) already transcode
        # on read — the returned string is already in the internal encoding.  Return it as-is.
        # For wrapper objects (e.g. EncodedBytesIO) that declare encodings but don't transcode on
        # read, the returned string will still be in ASCII-8BIT — fall through to tag + transcode.
        return line if int && line.encoding == int

        out_enc = @emit_encoding || external_encoding
        # Needed for the single-encoding case (int == nil) when the source declares an
        # external_encoding but returns ASCII-8BIT from #gets (wrapper IOs: EncodedBytesIO,
        # pipes, STDIN, decompression streams). maybe_transcode is a no-op when int is nil,
        # so this is the only step that tags the line in the correct external encoding —
        # otherwise reader.rb#enforce_utf8_encoding would misread the bytes as UTF-8.
        # Redundant on the transcoding-pair path (maybe_transcode force_encodes there too),
        # but the guard keeps it cheap. Covered by peekable_io_spec.rb frozen-exhausted
        # single-encoding test.
        line = line.force_encoding(out_enc) if out_enc && line.encoding != out_enc
        return maybe_transcode(line)
      end

      # Compute the output encoding once — used by both the detection and frozen paths.
      # For sources with no declared encoding (nil) we fall back to ASCII_8BIT rather
      # than assuming UTF-8 — the caller gets the raw bytes and can re-tag as needed.
      out_enc = @emit_encoding || external_encoding

      # ---------------------------------------------------------------------------
      # Auto-Detection phase (buffer not yet frozen):
      # Extend the buffer in @buffer_size chunks until the separator is found
      # or EOF.  No straddle detection needed — the extension absorbs any boundary.
      # @peek_pos never advances until we have a complete line, so the search always
      # covers the full unread portion of the ever-growing buffer.
      # ---------------------------------------------------------------------------
      unless @buffer_frozen
        loop do
          rest = @peek_buf.byteslice(@peek_pos..-1)
          rest.force_encoding(out_enc || Encoding::ASCII_8BIT)
          # NOTE: rest.b.index(sep.b) is the Ruby 2.6 compatible equivalent of rest.byteindex(sep)
          idx = rest.b.index(sep.b)
          if idx
            line = rest.byteslice(0, idx + sep.bytesize)
            @peek_pos += line.bytesize
            return maybe_transcode(line)
          end
          # Separator not found — fetch another chunk and search again.
          break unless extend_buffer!
        end
        # EOF: return remaining bytes as final line, or nil if nothing left.
        rest = @peek_buf.byteslice(@peek_pos..-1)
        return nil if rest.empty?

        @peek_pos = @peek_buf.bytesize
        return maybe_transcode(rest.force_encoding(out_enc || Encoding::ASCII_8BIT))
      end

      # ---------------------------------------------------------------------------
      # Frozen phase (processing): buffer has fixed content.
      # Search within the buffer; handle the separator straddling the buffer/@io
      # boundary for multi-byte separators (e.g. \r\n split across the edge).
      # ---------------------------------------------------------------------------
      rest = @peek_buf.byteslice(@peek_pos..-1)
      rest.force_encoding(out_enc || Encoding::ASCII_8BIT)
      # Use byteindex + byteslice — the buffer stores raw bytes and @peek_pos is a
      # byte offset. Separators are always ASCII, so byteindex is correct regardless
      # of the encoding tag.
      # NOTE: rest.b.index(sep.b) is the Ruby 2.6 compatible equivalent of rest.byteindex(sep)
      idx = rest.b.index(sep.b)
      if idx
        line = rest.byteslice(0, idx + sep.bytesize)
        @peek_pos += line.bytesize
        maybe_transcode(line)
      else
        @peek_pos = @peek_buf.bytesize # mark exhausted, keep buffer alive for rewind

        # Detect multi-byte separator (e.g. \r\n) split at the buffer boundary —
        # \r is the last byte of @peek_buf, \n is the first byte of @io.
        # byteindex found nothing because the separator straddles the boundary.
        # Check if the buffer tail matches any prefix of sep and read ahead to confirm.
        # For non-seekable IO: on a non-match the already-read bytes are prepended
        # to the remainder so no data is lost.
        if sep.bytesize > 1
          (sep.bytesize - 1).downto(1) do |prefix_len|
            next unless rest.b.end_with?(sep.b.byteslice(0, prefix_len))

            tail_needed = sep.b.byteslice(prefix_len..-1)
            peeked = @io.read(tail_needed.bytesize)

            if peeked.nil?
              combined = rest.b                        # EOF — nothing new to read
            elsif peeked.b == tail_needed
              combined = rest.b + tail_needed          # separator confirmed
            else
              # peeked bytes are content, not separator completion.
              # But peeked itself may end with a prefix of sep (e.g. peeked="\r"
              # when sep="\r\n"), meaning @io could begin with sep's tail ("\n").
              # Calling @io.gets(sep) from here would over-read past that boundary.
              # Instead, recursively check for a nested straddle in peeked.
              content = peeked.b
              nested_handled = false
              (sep.bytesize - 1).downto(1) do |n|
                next unless content.end_with?(sep.b.byteslice(0, n))

                confirmed_tail = @io.read(sep.bytesize - n)
                if confirmed_tail.nil?
                  # EOF — nothing more to read; content stays as-is
                elsif confirmed_tail.b == sep.b.byteslice(n..-1)
                  content += confirmed_tail.b # separator confirmed
                else
                  remainder = @io.gets(sep)
                  content = content + confirmed_tail.b + (remainder ? remainder.b : ''.b)
                end
                nested_handled = true
                break
              end
              unless nested_handled
                remainder = @io.gets(sep)
                content += (remainder ? remainder.b : ''.b)
              end
              combined = rest.b + content
            end
            return maybe_transcode(out_enc ? combined.force_encoding(out_enc) : combined)
          end
        end

        remainder = @io.gets(sep)
        combined = rest.b + (remainder ? remainder.b : ''.b)
        maybe_transcode(out_enc ? combined.force_encoding(out_enc) : combined)
      end
    end

    # Unlike gets, readline raises EOFError at end of file rather than returning nil.
    # Defaults to @options[:row_sep], never $/.
    def readline(sep = @options[:row_sep])
      line = gets(sep)
      raise EOFError, "end of file reached" if line.nil?

      line
    end

    def read(n = nil)
      # Delegate to @io only when (a) we never peeked, or (b) the buffer is
      # frozen and fully replayed. During auto-detection (not frozen) the
      # buffer must be extended even when @peek_pos has caught up to its end,
      # otherwise bytes read from @io are not appended to @peek_buf and a
      # subsequent rewind_buffer would lose them.
      return @io.read(n) if @peek_buf.nil?
      return @io.read(n) if @buffer_frozen && buffer_exhausted?

      buffered = @peek_buf.byteslice(@peek_pos..-1)
      out_enc = @emit_encoding || Encoding::ASCII_8BIT

      # All paths use binary concatenation then re-tag to avoid encoding mismatches.
      if n.nil?
        @peek_pos = @peek_buf.bytesize # consume all buffered bytes
        rest_from_io = @io.read
        appended = rest_from_io ? rest_from_io.b : ''.b
        @peek_buf << appended unless @buffer_frozen
        combined = buffered + appended
        maybe_transcode(combined.force_encoding(out_enc))
      elsif n == 0
        String.new.force_encoding(out_enc) # read(0) must not advance @peek_pos
      elsif buffered.bytesize >= n
        @peek_pos += n # advance exactly n, not the whole buffer
        maybe_transcode(buffered.byteslice(0, n).force_encoding(out_enc))
      else
        @peek_pos = @peek_buf.bytesize # consume all buffered bytes
        rest_from_io = @io.read(n - buffered.bytesize)
        appended = rest_from_io ? rest_from_io.b : ''.b
        @peek_buf << appended unless @buffer_frozen
        combined = buffered + appended
        maybe_transcode(combined.force_encoding(out_enc))
      end
    end

    def each_char(&block)
      return enum_for(:each_char) unless block_given?
      # Same guard as read(): only delegate when never peeked, or when frozen
      # and fully replayed. Otherwise we must extend the buffer so rewind_buffer
      # can replay the bytes during the parsing phase.
      return @io.each_char(&block) if @peek_buf.nil?
      return @io.each_char(&block) if @buffer_frozen && buffer_exhausted?

      rest = @peek_buf.byteslice(@peek_pos..-1)
      rest.force_encoding(@emit_encoding || external_encoding || Encoding::ASCII_8BIT)
      rest = maybe_transcode(rest) || rest
      rest.each_char(&block)
      @peek_pos = @peek_buf.bytesize # mark exhausted, keep buffer alive for rewind

      # Read remaining @io in chunks — avoids O(n²) string concatenation from
      # appending one byte at a time.  Row-sep detection only needs ASCII chars
      # (\n, \r) so codepoint boundaries at chunk edges are inconsequential.
      until @io.eof?
        chunk = @io.read(@buffer_size)
        break unless chunk

        @peek_buf << chunk.b unless @buffer_frozen
        chunk.force_encoding(@emit_encoding || external_encoding || Encoding::ASCII_8BIT)
        (maybe_transcode(chunk) || chunk).each_char(&block)
      end
    end

    def eof?
      return @io.eof? if buffer_exhausted?

      false # still have unread bytes in peek buffer
    end

    # Resets to the start of the peek buffer — never touches the underlying IO.
    # Since auto-detection happens at the very beginning, the buffer IS byte 0.
    # Works identically for files, StringIO, pipes, and any other source.
    #
    # Does NOT freeze the buffer — detection may call rewind_buffer multiple times
    # (once per pass) and must continue accumulating bytes beyond the initial
    # peek chunk.  Call freeze_buffer! explicitly when detection is complete.
    def rewind_buffer
      @peek_pos = 0
    end

    def rewind
      raise NoMethodError, "use rewind_buffer instead of rewind — PeekableIO does not seek the underlying IO"
    end

    # Freeze the buffer: signals that auto-detection is complete and normal
    # processing is beginning.  After this point, reads that go beyond the
    # buffered bytes delegate directly to @io without growing @peek_buf further.
    def freeze_buffer!
      @buffer_frozen = true
    end

    def close
      @io.close if @io.respond_to?(:close)
    end

    def external_encoding
      @io.respond_to?(:external_encoding) ? @io.external_encoding : nil
    end

    def internal_encoding
      @io.respond_to?(:internal_encoding) ? @io.internal_encoding : nil
    end

    private

    def buffer_exhausted?
      @peek_buf.nil? || @peek_pos >= @peek_buf.bytesize
    end

    # Append one @buffer_size chunk from @io to @peek_buf.
    # Returns true if bytes were added, false if @io was already at EOF.
    def extend_buffer!
      chunk = @io.read(@buffer_size)
      return false unless chunk && !chunk.empty?

      @peek_buf << chunk.b
      true
    end

    # Strip any BOM from the start of the raw (ASCII_8BIT-tagged) buffer bytes.
    # Doing this once here means all downstream code — auto-detection, the C
    # extension parser, remove_bom in file_io.rb — never sees BOM bytes.
    # Patterns ordered longest-first so UTF-32 is matched before UTF-16.
    BOM_PATTERNS = [
      "\x00\x00\xFE\xFF".b,  # UTF-32 BE
      "\xFF\xFE\x00\x00".b,  # UTF-32 LE
      "\xEF\xBB\xBF".b,      # UTF-8
      "\xFE\xFF".b,           # UTF-16 BE
      "\xFF\xFE".b,           # UTF-16 LE
    ].freeze

    def strip_bom(raw)
      BOM_PATTERNS.each do |bom|
        return raw.byteslice(bom.bytesize..-1) if raw.start_with?(bom)
      end
      raw
    end

    # Read up to MAX_ALIGN_BYTES extra bytes from @io until the buffer ends on a
    # complete codepoint boundary in @emit_encoding.
    #
    # For single-byte encodings (ISO-8859-1, ASCII) valid_encoding? is true
    # immediately, so no extra reads occur.
    #
    # Bounded to MAX_ALIGN_BYTES (4) to guard against malformed files: a corrupt
    # byte anywhere in the first peek chunk makes valid_encoding? permanently false.
    # Without the cap the loop would read the entire remaining file one byte at a
    # time before giving up.  4 bytes covers the largest codepoint in any Ruby-supported
    # variable-width encoding (UTF-8 max 4, UTF-32 4, UTF-16 surrogate pairs 4,
    # EUC-JP 3, Shift-JIS 2, GB18030 4).
    MAX_ALIGN_BYTES = 4

    def align_to_char_boundary(raw)
      MAX_ALIGN_BYTES.times do
        probe = raw.dup.force_encoding(@emit_encoding)
        return raw if probe.valid_encoding?

        extra = @io.read(1)
        break unless extra # EOF mid-codepoint — malformed input, stop here

        raw += extra.b
      end
      raw
    end

    # Apply external→internal transcoding to a string returned from the buffer.
    # The buffer stores raw bytes in the external encoding (@emit_encoding).
    # When the underlying IO was opened with a transcoding pair (e.g. r:iso-8859-1:utf-8),
    # callers expect strings in the internal encoding — the same as IO#gets returns.
    # No-op when there is no transcoding pair or no declared encoding.
    def maybe_transcode(str)
      return str unless str

      int = internal_encoding
      return str unless int && @emit_encoding && int != @emit_encoding

      str.force_encoding(@emit_encoding).encode(int, invalid: :replace, undef: :replace)
    end

    # Allow-list of @io methods safe to expose via method_missing.
    #
    # PeekableIO is an internal SmarterCSV utility; reader.rb is its only caller.
    # Every method SmarterCSV uses on a PeekableIO is either defined explicitly on
    # this class (peek, gets, read, each_char, readline, eof?, close, rewind_buffer,
    # freeze_buffer!, external_encoding, internal_encoding) or is on this list.
    #
    # Any other call — seek, pos=, lineno=, ungetc, ungetbyte, readpartial, sysread,
    # readlines, each_line, etc. — raises NoMethodError. That surfaces a future
    # maintainer's mistake loudly rather than silently desyncing @peek_pos from @io
    # and breaking replay-after-rewind_buffer.
    #
    # Extending this list is a deliberate contract change: add a method only when a
    # real caller inside SmarterCSV needs it.
    ALLOWED_METHODS = %i[encoding].freeze

    def respond_to_missing?(method, include_private = false)
      (ALLOWED_METHODS.include?(method) && @io.respond_to?(method, include_private)) || super
    end

    def method_missing(method, *args, &block)
      return super unless ALLOWED_METHODS.include?(method) && @io.respond_to?(method)

      @io.send(method, *args, &block)
    end
  end
end
