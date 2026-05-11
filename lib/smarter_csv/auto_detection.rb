# frozen_string_literal: true

module SmarterCSV
  module AutoDetection
    protected

    # If file has headers, then guesses column separator from headers.
    # Otherwise guesses column separator from contents.
    # Raises exception if none is found.
    def guess_column_separator(filehandle, options)
      delimiters = [',', "\t", ';', ':', '|']

      line = nil
      escaped_quote = Regexp.escape(options[:quote_char])
      has_header = options[:headers_in_file]
      candidates = Hash.new(0)
      count = has_header ? 1 : 5
      count.times do
        next_line = next_line_with_counts(filehandle, options)
        break if next_line.nil? # EOF reached (short files)

        line = next_line
        delimiters.each do |d|
          # Count only non-quoted occurrences of the delimiter
          non_quoted_text = line.split(/#{escaped_quote}[^#{escaped_quote}]*#{escaped_quote}/).join

          candidates[d] += non_quoted_text.scan(d).count
        end
      end
      # No lines were read at all — empty file or stream.
      # Return a safe default and let process_headers raise EmptyFileError.
      return ',' if line.nil?

      if candidates.values.max == 0
        # if the header only contains word characters and whitespace, assume comma separator
        return ',' if line.chomp(options[:row_sep]) =~ /^[\w\s]+$/

        raise SmarterCSV::NoColSepDetected
      end

      candidates.key(candidates.values.max)
    end

    # Lower bound on auto_row_sep_chars. Below this the initial scan would be
    # too small to reliably catch a row separator on the very first read on
    # most real-world CSV files. Most well-formed CSVs reveal a clear majority
    # within ~200 bytes; 512 gives comfortable headroom while keeping cheap
    # files cheap.
    MIN_AUTO_ROW_SEP_CHARS = 512

    # Default auto_row_sep_chars. Sized to cover wide-header CSVs (e.g. 100+
    # columns) in a single read so escalation rarely fires. 4096 also matches
    # a typical filesystem block, so the OS-level read cost is the same as a
    # smaller request.
    DEFAULT_AUTO_ROW_SEP_CHARS = 4096

    # Upper bound on auto_row_sep_chars. Serves three roles:
    #   1. The hard cap on the user-facing `auto_row_sep_chars` option.
    #   2. The cap on the doubling escalation inside guess_line_ending —
    #      a single chunk read never exceeds this.
    #   3. The hard cap on total bytes scanned during auto-detection
    #      (`break if buf.bytesize >= MAX_AUTO_ROW_SEP_CHARS`).
    # All three roles use the same value because beyond this point further
    # scanning would not improve detection accuracy and only delays parsing.
    MAX_AUTO_ROW_SEP_CHARS = 65_536

    # Guess the row separator ("\n", "\r\n", or "\r") by counting occurrences
    # outside of quoted regions, scanning each chunk only once and accumulating
    # counts across iterations.
    #
    # Reads one chunk of options[:auto_row_sep_chars] bytes at a time and
    # grows up to MAX_AUTO_ROW_SEP_CHARS bytes total while no candidate has
    # a clear majority (count > sum of the others).
    #
    # State carried across iterations:
    #   * crlf, lf, cr — running counts; never reset
    #   * in_quote    — true if a previous chunk ended inside a quoted region
    #   * pending_cr  — true if a previous chunk's last byte was a lone "\r"
    #                   (deferred so it can pair with a leading "\n" of the
    #                   next chunk without an extra read).
    #
    # Falls back to "\n" (and emits a warning unless verbose: :quiet) when:
    #   * no known separator is found within MAX_AUTO_ROW_SEP_CHARS bytes — e.g. a file
    #     that uses an exotic separator like "\u2028"; or
    #   * a tie between candidates persists across MAX_AUTO_ROW_SEP_CHARS bytes.
    #
    # The fallback preserves 14 years of permissive behavior; the warning lets
    # infrastructure code (logs, captured stderr) surface the ambiguity.
    def guess_line_ending(filehandle, options)
      q = Regexp.escape(options[:quote_char])
      # Combined regex: matches complete "..." pairs AND unclosed "...\z (open
      # quote followed by content to end of string). One gsub pass strips both
      # cases; quote count parity tells us whether an unclosed open existed.
      # /n flag: byte-level matching, encoding-agnostic.
      quoted_re = /#{q}[^#{q}]*(?:#{q}|\z)/n
      quote_str = options[:quote_char].b
      # Adaptive doubling: the first read is auto_row_sep_chars bytes (default 4096).
      # Iter 2 reuses the same size so files with a clear separator slightly past
      # the initial chunk resolve cheaply; iter 3+ doubles each iteration up to
      # MAX_AUTO_ROW_SEP_CHARS.
      #
      # Read pattern with default auto_row_sep_chars = 4096:
      #   iter | chunk | cumulative
      #     1  |  4096 |   4096
      #     2  |  4096 |   8192
      #     3  |  8192 |  16384
      #     4  | 16384 |  32768
      #     5  | 32768 |  65536  (loop ends at MAX_AUTO_ROW_SEP_CHARS)
      #
      # MIN_AUTO_ROW_SEP_CHARS is the defensive floor — catches direct callers
      # that bypass option validation (e.g. tests calling via send). Through the
      # public process_options pipeline, validation already enforces this floor,
      # so this .max is inert in normal use.
      chunk_size = [options[:auto_row_sep_chars].to_i, MIN_AUTO_ROW_SEP_CHARS].max
      bytes_read = false
      total_bytes = 0
      crlf = lf = cr = 0
      in_quote = false       # carries across chunks; an open quote with no close
      pending_cr = false     # carries across chunks; "\r" deferred for "\r\n" pairing
      iter = 0

      loop do
        part = filehandle.read(chunk_size)
        break if part.nil? || part.empty?

        bytes_read = true
        total_bytes += part.bytesize

        # Resolve a "\r" left pending from the previous chunk's last byte.
        # If the new chunk starts with "\n", the pair is "\r\n"; otherwise
        # the deferred "\r" was a lone "\r" and the new first byte is
        # processed below. (pending_cr and in_quote can never both be true
        # at the start of an iteration — see the open-quote handling below.)
        if pending_cr
          pending_cr = false
          if part.getbyte(0) == 0x0A # \n
            crlf += 1
            part = part.byteslice(1, part.bytesize - 1)
          else
            cr += 1
            # part stays as-is; the new first byte is processed below.
          end
        end

        # Fast path: chunk has no quote char AND we're not carrying an open
        # quote from a previous chunk. Skip the gsub + index + .b machinery
        # and count separators directly — most CSV chunks contain no quote
        # chars. (`include?` is one C-level byte scan, vs gsub + index = two
        # passes plus a string copy.)
        if !in_quote && !part.include?(quote_str)
          unquoted = part
          if unquoted.end_with?("\r")
            pending_cr = true
            unquoted = unquoted.byteslice(0, unquoted.bytesize - 1)
          end
          delta_crlf = unquoted.scan("\r\n").size
          delta_lf   = unquoted.count("\n") - delta_crlf
          delta_cr   = unquoted.count("\r") - delta_crlf
          crlf += delta_crlf
          lf   += delta_lf
          cr   += delta_cr
        else
          # Slow path: chunk contains quote chars or we're carrying in_quote
          # state from a previous chunk. Convert to binary so index/byteslice
          # are byte-level (safe even with multibyte UTF-8 content before the
          # quote position).
          part = part.b

          if in_quote
            close_idx = part.index(quote_str)
            if close_idx
              in_quote = false
              part = part.byteslice(close_idx + 1, part.bytesize - close_idx - 1)
            else
              # Whole chunk is still inside the quote.
              part = nil
            end
          end

          if part && !part.empty?
            # Single regex pass: gsub with the combined regex strips every
            # complete "..." pair AND, if there's an unclosed open quote at
            # the end, strips "...\z too. After this, no quote chars remain
            # in `unquoted`.
            unquoted = part.gsub(quoted_re, '')

            # Parity check on the original chunk's quote count: an odd count
            # means an unclosed open quote existed (and the gsub stripped its
            # content along with the open). Set in_quote so the next chunk
            # will look for the close. (count is a fast C-level byte scan.)
            in_quote = true if part.count(quote_str).odd?

            if unquoted.end_with?("\r".b)
              if in_quote
                # The byte right after this trailing "\r" was the open quote
                # char (NOT "\n"), so the "\r" is a lone cr — count it now.
                # Deferring would mispair against the next chunk's first
                # byte, which is inside the (now-open) quoted region.
                cr += 1
              else
                # No open quote — safe to defer trailing "\r" so it can pair
                # with the next chunk's leading "\n" if any.
                pending_cr = true
              end
              unquoted = unquoted.byteslice(0, unquoted.bytesize - 1)
            end

            # Count separators in the new bytes and add to running totals.
            delta_crlf = unquoted.scan("\r\n".b).size
            delta_lf   = unquoted.count("\n") - delta_crlf
            delta_cr   = unquoted.count("\r") - delta_crlf
            crlf += delta_crlf
            lf   += delta_lf
            cr   += delta_cr
          end
        end

        # Clear majority: winner strictly greater than the sum of the others.
        return "\r\n" if crlf > lf + cr
        return "\n"   if lf   > crlf + cr
        return "\r"   if cr   > crlf + lf

        break if total_bytes >= MAX_AUTO_ROW_SEP_CHARS

        # Iter 2 keeps the iter-1 chunk size; iter 3+ doubles each iteration,
        # capped at MAX_AUTO_ROW_SEP_CHARS.
        iter += 1
        chunk_size = [chunk_size * 2, MAX_AUTO_ROW_SEP_CHARS].min if iter >= 2
      end

      # Empty stream — return harmless fallback; downstream raises EmptyFileError.
      return "\n" unless bytes_read

      # If we exited with a deferred "\r" (EOF or cap reached and no following
      # byte to pair it with), count it as a lone "\r" now and re-check majority.
      # Without this, a file ending in a lone "\r" with no other separators would
      # fall through to the no-clear-row-sep warning instead of returning "\r".
      if pending_cr
        cr += 1
        return "\r\n" if crlf > lf + cr
        return "\n"   if lf   > crlf + cr
        return "\r"   if cr   > crlf + lf
      end

      unless options[:verbose] == :quiet
        if crlf == 0 && lf == 0 && cr == 0
          record_warning(type: :row_sep, code: :no_row_sep_found, severity: :error) do
            "no row separator found in first #{total_bytes} bytes; " \
            "defaulting to \"\\n\". Pass row_sep: explicitly if this is wrong."
          end
        else
          record_warning(type: :row_sep, code: :no_clear_row_sep, severity: :error) do
            "no clear row separator in first #{total_bytes} bytes " \
            "(saw #{lf}×\"\\n\", #{crlf}×\"\\r\\n\", #{cr}×\"\\r\"); defaulting to \"\\n\". " \
            "Pass row_sep: explicitly if this is wrong."
          end
        end
      end
      "\n"
    end
  end
end
