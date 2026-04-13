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
  #   3. gets/read/each_char — drain the buffer first, then delegate to underlying IO
  #   4. once drained, @peek_buf is set to nil and all reads go directly to @io
  #      with a single nil check — zero overhead for the rest of the file
  #
  class PeekableIO
    # 16KB is enough for separator detection on any real-world CSV header.
    DEFAULT_PEEK_SIZE = 16_384

    def initialize(io)
      @io = io
      @peek_buf = nil   # nil = buffer not yet filled / already drained
      @peek_pos = 0
      @emit_encoding = nil  # encoding of strings returned by @io.read — set on first peek
    end

    # Read up to n bytes into the buffer and return them.
    # Called once before auto-detection begins.
    #
    # Works for any IO source — files, StringIO, pipes, Zlib streams, etc.
    # The BOM (if any) is stripped immediately so all downstream code is clean.
    # For transcoded streams (e.g. r:iso-8859-1:utf-8), the raw bytes are
    # converted to the internal encoding in-place; @emit_encoding records the
    # final encoding so read-out can re-tag strings correctly.
    def peek(n = DEFAULT_PEEK_SIZE)
      # Idempotent: a second peek call returns the existing buffer without reading
      # more from @io.  Calling peek twice would otherwise overwrite the buffer and
      # silently drop any unconsumed bytes from the first peek.
      return @peek_buf.dup.force_encoding(@emit_encoding || Encoding::BINARY) if @peek_buf

      # read(n) fetches raw bytes as ASCII-8BIT regardless of the file's declared
      # encoding — this is what we want because it works even for files that begin
      # with non-UTF-8 BOMs (\xFF\xFE etc.) that would cause gets(nil,n) on a
      # r:utf-8 handle to stop after the first invalid byte.
      #
      # After stripping the BOM we transcode the buffer ourselves if the stream
      # uses a transcoding pair (e.g. r:iso-8859-1:utf-8): read(n) does NOT
      # transcode, so we encode the raw external-encoding bytes to internal_encoding.
      chunk = @io.read(n)
      if chunk && !chunk.empty?
        raw = strip_bom(chunk.b)
        ext = external_encoding
        int = internal_encoding
        if ext && int && ext != int
          # Transcoded stream: raw bytes are in external_encoding; convert to internal.
          raw = raw.dup.force_encoding(ext).encode(int).b
          @emit_encoding = int
        else
          # nil for binary/untagged sources (pipes, STDIN without explicit encoding).
          # Downstream force_encoding calls have their own fallback chain.
          @emit_encoding = ext
        end
        # Ensure the buffer ends on a complete character boundary.
        # If peek(n) stopped mid-codepoint, read one byte at a time until the
        # buffer is valid in its declared encoding. This prevents gets / each_char
        # from handing a truncated sequence to the caller and positioning @io at
        # a continuation byte — which can raise or corrupt data for strict encodings.
        # Skipped when encoding is unknown (nil) or single-byte (every byte is valid).
        raw = align_to_char_boundary(raw) if @emit_encoding
        @peek_buf = raw
        @peek_pos = 0
      end
      # Bug 3 fix: return the full buffered content (BOM-stripped + char-aligned)
      # rather than the original chunk so callers see what was actually consumed.
      @peek_buf ? @peek_buf.dup.force_encoding(@emit_encoding || Encoding::BINARY) : chunk
    end

    # Returns the next line up to and including sep.
    # Hot path: @peek_buf is nil (never peeked) or exhausted — delegate directly to @io.
    # The buffer is never nilled out by read methods so that rewind always works during
    # the auto-detection phase. @peek_pos advancing past bytesize is the exhaustion signal.
    #
    # NOTE: sep must be a String. gets(nil) — which reads until EOF in Ruby IO — is not
    # supported; smarter_csv always passes an explicit row separator string.
    def gets(sep = $/, **kwargs)
      return @io.gets(sep, **kwargs) if @peek_buf.nil? || @peek_pos >= @peek_buf.bytesize

      # Compute the output encoding once; both the found-in-buffer and the
      # else/boundary paths use the same value for consistency.
      # For sources with no declared encoding (nil) we fall back to BINARY rather
      # than assuming UTF-8 — the caller gets the raw bytes and can re-tag as needed.
      out_enc = @emit_encoding || external_encoding
      rest = @peek_buf.byteslice(@peek_pos..)
      rest.force_encoding(out_enc || Encoding::BINARY)
      # Use byteindex + byteslice — the buffer stores raw bytes and @peek_pos is a
      # byte offset. Separators are always ASCII, so byteindex is correct regardless
      # of the encoding tag.
      idx = rest.byteindex(sep)
      if idx
        line = rest.byteslice(0, idx + sep.bytesize)
        @peek_pos += line.bytesize
        line
      else
        @peek_pos = @peek_buf.bytesize  # mark exhausted, keep buffer alive for rewind

        # Bug 1 fix: detect multi-byte separator (e.g. \r\n) split at the buffer
        # boundary — \r is the last byte of @peek_buf, \n is the first byte of @io.
        # byteindex found nothing because the separator straddles the boundary.
        # Check if the buffer tail matches any prefix of sep and read ahead to confirm.
        # For non-seekable IO: on a non-match the already-read bytes are prepended
        # to the remainder so no data is lost.
        if sep.bytesize > 1
          (sep.bytesize - 1).downto(1) do |prefix_len|
            next unless rest.b.end_with?(sep.b.byteslice(0, prefix_len))

            tail_needed = sep.b.byteslice(prefix_len..)
            peeked = @io.read(tail_needed.bytesize)

            combined =
              if peeked.nil?
                rest.b                                                    # EOF after rest
              elsif peeked.b == tail_needed
                rest.b + tail_needed                                      # separator confirmed
              else
                remainder = @io.gets(sep, **kwargs)
                rest.b + peeked.b + (remainder ? remainder.b : ''.b)     # peeked was content
              end
            return out_enc ? combined.force_encoding(out_enc) : combined
          end
        end

        # Bug 4 fix: concatenate in binary then re-tag to avoid
        # Encoding::CompatibilityError when @emit_encoding is nil (source has no
        # declared encoding) and @io.gets returns ASCII-8BIT with bytes >= 128,
        # while rest was force-encoded as UTF-8 via the fallback chain above.
        remainder = @io.gets(sep, **kwargs)
        combined = rest.b + (remainder ? remainder.b : ''.b)
        out_enc ? combined.force_encoding(out_enc) : combined
      end
    end

    alias readline gets

    def read(n = nil)
      return @io.read(n) if @peek_buf.nil? || @peek_pos >= @peek_buf.bytesize

      buffered = @peek_buf.byteslice(@peek_pos..)
      out_enc = @emit_encoding || Encoding::BINARY

      # All paths use binary concatenation then re-tag to avoid encoding mismatches.
      if n.nil?
        @peek_pos = @peek_buf.bytesize  # consume all buffered bytes
        rest_from_io = @io.read
        combined = buffered + (rest_from_io ? rest_from_io.b : ''.b)
        combined.force_encoding(out_enc)
      elsif n == 0
        String.new.force_encoding(out_enc)  # read(0) must not advance @peek_pos
      elsif buffered.bytesize >= n
        @peek_pos += n                 # advance exactly n, not the whole buffer
        buffered.byteslice(0, n).force_encoding(out_enc)
      else
        @peek_pos = @peek_buf.bytesize  # consume all buffered bytes
        rest_from_io = @io.read(n - buffered.bytesize)
        combined = buffered + (rest_from_io ? rest_from_io.b : ''.b)
        combined.force_encoding(out_enc)
      end
    end

    def each_char
      return enum_for(:each_char) unless block_given?
      return @io.each_char { |c| yield c } if @peek_buf.nil? || @peek_pos >= @peek_buf.bytesize

      rest = @peek_buf.byteslice(@peek_pos..)
      rest.force_encoding(@emit_encoding || external_encoding || Encoding::BINARY)
      rest.each_char { |c| yield c }
      @peek_pos = @peek_buf.bytesize  # mark exhausted, keep buffer alive for rewind
      @io.each_char { |c| yield c }
    end

    def eof?
      return @io.eof? if @peek_buf.nil? || @peek_pos >= @peek_buf.bytesize

      false  # still have unread bytes in peek buffer
    end

    # Resets to the start of the peek buffer — never touches the underlying IO.
    # Since auto-detection happens at the very beginning, the buffer IS byte 0.
    # Works identically for files, StringIO, pipes, and any other source.
    def rewind
      @peek_pos = 0
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

    # Strip any BOM from the start of the raw (BINARY-tagged) buffer bytes.
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
        return raw.byteslice(bom.bytesize..) if raw.start_with?(bom)
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
        break unless extra            # EOF mid-codepoint — malformed input, stop here
        raw = raw + extra.b
      end
      raw
    end

    def respond_to_missing?(method, include_private = false)
      @io.respond_to?(method, include_private) || super
    end

    def method_missing(method, *args, **kwargs, &block)
      @io.send(method, *args, **kwargs, &block)
    end
  end
end
