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
    # in the unquoted portion of the stream.
    #
    # Reads one chunk of options[:auto_row_sep_chars] bytes at a time and
    # grows the buffer up to MAX_AUTO_ROW_SEP_CHARS bytes while no candidate has a clear
    # majority (count > sum of the others).
    #
    # When a chunk ends exactly on "\r", one extra byte is read so a lone
    # "\r" is never mistaken for the first half of "\r\n".
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
      quoted_re = /#{q}[^#{q}]*#{q}/
      # Adaptive doubling: the first read is auto_row_sep_chars bytes (default 512).
      # Iter 2 reuses the same size so files with a clear separator slightly past
      # the initial chunk resolve cheaply; iter 3+ doubles each iteration up to
      # MAX_AUTO_ROW_SEP_CHARS.
      #
      # Read pattern with default auto_row_sep_chars = 512:
      #   iter | chunk | cumulative
      #     1  |   512 |    512
      #     2  |   512 |   1024
      #     3  |  1024 |   2048
      #     4  |  2048 |   4096
      #     5  |  4096 |   8192
      #     6  |  8192 |  16384
      #     7  | 16384 |  32768
      #     8  | 32768 |  65536  (loop ends at MAX_AUTO_ROW_SEP_CHARS)
      #
      # MIN_AUTO_ROW_SEP_CHARS is the defensive floor — catches direct callers
      # that bypass option validation (e.g. tests calling via send). Through the
      # public process_options pipeline, validation already enforces this floor,
      # so this .max is inert in normal use.
      chunk_size = [options[:auto_row_sep_chars].to_i, MIN_AUTO_ROW_SEP_CHARS].max
      buf = String.new
      bytes_read = false
      crlf = lf = cr = 0
      iter = 0

      loop do
        part = filehandle.read(chunk_size)
        break if part.nil? || part.empty?

        bytes_read = true
        buf << part

        if buf.end_with?("\r")
          extra = filehandle.read(1)
          buf << extra if extra
        end

        unquoted = buf.gsub(quoted_re, '')
        crlf = unquoted.scan("\r\n").size
        lf   = unquoted.count("\n") - crlf
        cr   = unquoted.count("\r") - crlf

        # Clear majority: winner strictly greater than the sum of the others.
        return "\r\n" if crlf > lf + cr
        return "\n"   if lf   > crlf + cr
        return "\r"   if cr   > crlf + lf

        break if buf.bytesize >= MAX_AUTO_ROW_SEP_CHARS

        # Iter 2 keeps the iter-1 chunk size; iter 3+ doubles each iteration,
        # capped at MAX_AUTO_ROW_SEP_CHARS.
        iter += 1
        chunk_size = [chunk_size * 2, MAX_AUTO_ROW_SEP_CHARS].min if iter >= 2
      end

      # Empty stream — return harmless fallback; downstream raises EmptyFileError.
      return "\n" unless bytes_read

      unless options[:verbose] == :quiet
        if crlf == 0 && lf == 0 && cr == 0
          record_warning(type: :row_sep, code: :no_row_sep_found, severity: :error) do
            "no row separator found in first #{buf.bytesize} bytes; " \
            "defaulting to \"\\n\". Pass row_sep: explicitly if this is wrong."
          end
        else
          record_warning(type: :row_sep, code: :no_clear_row_sep, severity: :error) do
            "no clear row separator in first #{buf.bytesize} bytes " \
            "(saw #{lf}×\"\\n\", #{crlf}×\"\\r\\n\", #{cr}×\"\\r\"); defaulting to \"\\n\". " \
            "Pass row_sep: explicitly if this is wrong."
          end
        end
      end
      "\n"
    end
  end
end
