# frozen_string_literal: true

module SmarterCSV
  module Parser
    EMPTY_STRING = '' # already frozen
    # Optimization #13: byteindex (byte-position search) was added in Ruby 3.2.
    # When available, it lets Opt #10/#12 skip-ahead use byte offsets directly —
    # no conversion from byte position to character position needed.
    #
    # Restricted to MRI Ruby (RUBY_ENGINE == 'ruby'): JRuby and TruffleRuby implement
    # byteindex but require the offset to land on a character boundary. Our byte-level
    # loop advances i one byte at a time, so i can point to a UTF-8 continuation byte
    # (0x80–0xBF) when Opt #10/#12 fires — which raises IndexError on those runtimes.
    # The inline getbyte fallback below is correct for all Ruby implementations.
    BYTEINDEX_AVAILABLE = RUBY_ENGINE == 'ruby' && String.method_defined?(:byteindex)

    protected

    ###
    ### Thin wrapper around C-extension
    ###
    ### NOTE: we are no longer passing-in header_size
    ###
    def parse(line, options, header_size = nil)
      # puts "SmarterCSV.parse OPTIONS: #{options[:acceleration]}" if options[:verbose]
      if options[:quote_escaping] == :auto
        parse_with_auto_fallback(line, options, header_size)
      else
        has_quotes = line.include?(options[:quote_char])

        if options[:acceleration] && has_acceleration
          # :nocov:
          elements = parse_csv_line_c(line, options[:col_sep], options[:quote_char], header_size, has_quotes, options[:strip_whitespace], options[:quote_escaping] == :backslash, options[:quote_boundary] == :standard, options[:row_sep])
          [elements, elements.size]
          # :nocov:
        else
          # puts "WARNING: SmarterCSV is using un-accelerated parsing of lines. Check options[:acceleration]"
          parse_csv_line_ruby(line, options, header_size, has_quotes)
        end
      end
    end

    def parse_with_auto_fallback(line, options, header_size = nil)
      # Optimization #4: cache merged options hashes for :auto mode
      @quote_escaping_backslash ||= options.merge(quote_escaping: :backslash)
      @quote_escaping_double    ||= options.merge(quote_escaping: :double_quotes)

      # Optimization #5: if the line contains no backslash, backslash escaping cannot
      # affect parsing (a backslash only matters immediately before a quote char).
      # RFC 4180 and backslash modes give identical results — skip the try-backslash
      # dance and call directly with RFC options (tighter C inner loop + memchr).
      # has_quotes is only needed for the Ruby fallback path — C computes it internally.
      unless line.include?('\\')
        if options[:acceleration] && has_acceleration
          # :nocov:
          elements = parse_csv_line_c(line, options[:col_sep], options[:quote_char], header_size, false, options[:strip_whitespace], false, options[:quote_boundary] == :standard, options[:row_sep])
          return [elements, elements.size]
          # :nocov:
        else
          has_quotes = line.include?(options[:quote_char])
          return parse_csv_line_ruby(line, @quote_escaping_double, header_size, has_quotes)
        end
      end

      # Line has a backslash — try backslash-escape interpretation first.
      # has_quotes only needed for Ruby fallback path.
      has_quotes = line.include?(options[:quote_char]) unless options[:acceleration] && has_acceleration

      result = begin
        # Try backslash-escape interpretation first
        if options[:acceleration] && has_acceleration
          # :nocov:
          elements = parse_csv_line_c(line, options[:col_sep], options[:quote_char], header_size, false, options[:strip_whitespace], true, options[:quote_boundary] == :standard, options[:row_sep])
          [elements, elements.size]
          # :nocov:
        else
          parse_csv_line_ruby(line, @quote_escaping_backslash, header_size, has_quotes)
        end
      rescue MalformedCSV
        # Backslash raised a hard error — fall back to RFC 4180 immediately
        if options[:acceleration] && has_acceleration
          # :nocov:
          elements = parse_csv_line_c(line, options[:col_sep], options[:quote_char], header_size, false, options[:strip_whitespace], false, options[:quote_boundary] == :standard, options[:row_sep])
          return [elements, elements.size]
          # :nocov:
        else
          return parse_csv_line_ruby(line, @quote_escaping_double, header_size, has_quotes)
        end
      end

      # Backslash sees unclosed quote (-1): RFC may still close it (e.g. header "val\")
      if result[1] == -1
        rfc_result = if options[:acceleration] && has_acceleration
                       # :nocov:
                       elements = parse_csv_line_c(line, options[:col_sep], options[:quote_char], header_size, false, options[:strip_whitespace], false, options[:quote_boundary] == :standard, options[:row_sep])
                       [elements, elements.size]
                       # :nocov:
                     else
                       parse_csv_line_ruby(line, @quote_escaping_double, header_size, has_quotes)
                     end
        return rfc_result unless rfc_result[1] == -1
        # Both agree line is incomplete → propagate -1
      end

      result
    end

    # Parse a CSV line directly into a hash, with support for extra columns.
    # Returns [hash_or_nil, data_size] where hash is nil if all values are blank.
    def parse_line_to_hash(line, headers, options)
      if options[:quote_escaping] == :auto
        parse_line_to_hash_auto(line, headers, options)
      else
        if options[:acceleration] && has_acceleration
          # :nocov:
          parse_line_to_hash_c(line, headers, options)
          # :nocov:
        else
          has_quotes = line.include?(options[:quote_char])
          parse_line_to_hash_ruby(line, headers, options, has_quotes)
        end
      end
    end

    def parse_line_to_hash_auto(line, headers, options)
      # Optimization #4: cache merged options hashes for :auto mode
      @quote_escaping_backslash ||= options.merge(quote_escaping: :backslash)
      @quote_escaping_double    ||= options.merge(quote_escaping: :double_quotes)

      if options[:acceleration] && has_acceleration
        # :nocov:
        # C path: zero Ruby string scanning on the hot path.
        # C handles Opt #5 internally — if backslash mode is requested but the line
        # contains no backslash, C automatically downgrades to RFC mode in Section 5
        # (enabling the memchr-inside-quotes optimisation). For unquoted lines, Section 4
        # fast path is taken and allow_escaped_quotes is irrelevant anyway.
        result = parse_line_to_hash_c(line, headers, @quote_escaping_backslash)
        if result[1] == -1 && line.include?('\\')
          # Backslash mode sees unclosed quote on a line that contains a backslash.
          # RFC 4180 may close it differently (e.g. "val\" is open in backslash
          # mode but closed in RFC mode). Only try RFC when a backslash is present —
          # if there is no backslash, both modes give identical results and the extra
          # call is wasted work (common case: embedded-newline partial stitching lines).
          rfc_result = parse_line_to_hash_c(line, headers, @quote_escaping_double)
          return rfc_result unless rfc_result[1] == -1
          # Both agree line is incomplete → propagate [nil, -1]
        end
        return result
        # :nocov:
      end

      # Ruby fallback path: explicit backslash/quote checks still needed
      has_quotes = line.include?(options[:quote_char])
      unless line.include?('\\')
        return parse_line_to_hash_ruby(line, headers, @quote_escaping_double, has_quotes)
      end

      result = begin
        parse_line_to_hash_ruby(line, headers, @quote_escaping_backslash, has_quotes)
      rescue MalformedCSV
        return parse_line_to_hash_ruby(line, headers, @quote_escaping_double, has_quotes)
      end

      # Backslash path sees an unclosed quote ([nil, -1]): RFC 4180 may still close
      # the field — e.g. a field ending with \" is open in backslash mode but closed
      # in RFC mode. Try RFC; if it also returns -1 both agree the line is incomplete.
      if result[1] == -1
        rfc_result = parse_line_to_hash_ruby(line, headers, @quote_escaping_double, has_quotes)
        return rfc_result unless rfc_result[1] == -1
        # Both interpretations agree the line is incomplete → propagate [nil, -1]
      end

      result
    end

    # Ruby implementation of parse_line_to_hash
    def parse_line_to_hash_ruby(line, headers, options, has_quotes = false)
      return [nil, 0] if line.nil?

      # Chomp trailing row separator
      line = line.chomp(options[:row_sep]) if options[:row_sep]

      col_sep = options[:col_sep]
      strip   = options[:strip_whitespace]
      prefix  = options[:missing_header_prefix]

      # Optimization #11: for unquoted lines, build the hash in one pass directly
      # from String#split — no intermediate array returned from parse_csv_line_ruby
      # and no second iteration to convert array → hash. Saves one Array allocation
      # + one full-row iteration per row (most impactful on wide-column files).
      unless has_quotes || col_sep == ' '
        fields = line.split(col_sep, -1)
        n = fields.size

        if options[:remove_empty_hashes]
          all_blank = fields.empty? || fields.all? { |v| v.strip.empty? }
          return [nil, n] if all_blank
        end

        hash = {}
        i = 0
        while i < n
          hash[i < headers.size ? headers[i] : :"#{prefix}#{i + 1}"] = strip ? fields[i].strip : fields[i]
          i += 1
        end

        unless options[:remove_empty_values]
          while i < headers.size
            hash[headers[i]] = nil
            i += 1
          end
        end

        return [hash, n]
      end

      # Quoted/complex path: parse into elements array, then build hash.
      elements, data_size = parse_csv_line_ruby(line, options, nil, has_quotes)
      return [nil, -1] if data_size == -1 # unclosed quote at EOL → caller stitches next line

      # Optimization #6: elements are always String or nil from parse_csv_line_ruby,
      # so .to_s is unnecessary. If strip_whitespace is on, fields are already
      # stripped, so .strip is also redundant — just check .empty?.
      if options[:remove_empty_hashes]
        all_blank = if strip
                      elements.empty? || elements.all? { |v| v.nil? || v.empty? }
                    else
                      elements.empty? || elements.all? { |v| v.nil? || v.strip.empty? }
                    end
        return [nil, data_size] if all_blank
      end

      # Build the hash — integer-index while loop avoids enumerator overhead vs each_with_index
      n = elements.size
      hash = {}
      i = 0
      while i < n
        hash[i < headers.size ? headers[i] : :"#{prefix}#{i + 1}"] = elements[i]
        i += 1
      end

      # Add nil for missing columns only when remove_empty_values is false
      # (when true, nils would be removed anyway by hash_transformations)
      unless options[:remove_empty_values]
        while i < headers.size
          hash[headers[i]] = nil
          i += 1
        end
      end

      [hash, data_size]
    end

    # ------------------------------------------------------------------
    # Ruby equivalent of the C-extension for parse_line
    #
    # parses a single line: either a CSV header and body line
    # - quoting rules compared to RFC-4180 are somewhat relaxed
    # - we are not assuming that quotes inside a fields need to be doubled
    # - we are not assuming that all fields need to be quoted (0 is even)
    # - works with multi-char col_sep
    #
    # NOTE: we are no longer passing-in header_size
    #
    # - if header_size was given, only up to header_size fields are parsed
    #
    #     We used header_size for parsing the body lines to make sure we always match the number of headers
    #     in case there are trailing col_sep characters in line
    #
    #     the purpose of the max_size parameter was to handle a corner case where
    #     CSV lines contain more fields than the header. In which case the remaining fields in the line were ignored
    #
    # Our convention is that empty fields are returned as empty strings, not as nil.

    def parse_csv_line_ruby(line, options, header_size = nil, has_quotes = false)
      return [[], 0] if line.nil?

      col_sep = options[:col_sep]
      strip = options[:strip_whitespace]

      # Ensure has_quotes is set correctly (callers via parse/parse_line_to_hash
      # always pass this, but direct callers may not)
      # rubocop:disable Style/OrAssignment
      has_quotes = line.include?(options[:quote_char]) unless has_quotes
      # rubocop:enable Style/OrAssignment

      # Optimization #7: when line has no quotes, use String#split (C-implemented)
      # to bypass the entire character-by-character loop.
      # Note: String#split(" ") has special whitespace-collapsing behavior in Ruby,
      # so we must use a literal string pattern only for non-space separators,
      # or fall through to the character loop for space separators.
      unless has_quotes || col_sep == ' '
        if header_size && header_size <= 0
          return [[], 0]
        end

        elements = line.split(col_sep, -1) # -1 preserves trailing empty fields
        elements = elements[0, header_size] if header_size
        elements.map!(&:strip) if strip
        return [elements, elements.size]
      end

      # Quoted-line path: character-by-character parsing required
      line_size = line.size
      col_sep_size = col_sep.size
      quote = options[:quote_char]
      elements = []
      start = 0
      i = 0

      backslash_count = 0
      in_quotes = false
      allow_escaped_quotes = options[:quote_escaping] == :backslash
      quote_boundary_standard = options[:quote_boundary] == :standard
      field_started = false # for boundary tracking (standard mode only)
      row_sep = options[:row_sep]
      row_sep_size = row_sep.is_a?(String) ? row_sep.size : 0

      # Optimization #1: for the common single-char separator, use direct
      # character comparison instead of allocating a substring via line[i...i+n].
      if col_sep_size == 1
        # Optimization #13: byte-level indexing for single-char separator.
        # col_sep and quote_char are both validated to be single-byte at option
        # parsing time. UTF-8 multi-byte continuation bytes (0x80–0xBF) never
        # alias ASCII delimiter bytes (0x00–0x7F), so byte scanning is safe for
        # UTF-8 strings with ASCII delimiters — no String allocation per character.
        col_sep_byte     = col_sep.getbyte(0)
        quote_byte       = quote.getbyte(0)
        bytesize         = line.bytesize
        row_sep_bytesize = row_sep.is_a?(String) ? row_sep.bytesize : 0

        while i < bytesize
          # Optimization #10: inside a quoted field with no backslash escaping, jump
          # directly to the next quote character using byteindex (C-level scan).
          # Avoids per-character Ruby iteration through long field content.
          if in_quotes && !allow_escaped_quotes
            next_q = if BYTEINDEX_AVAILABLE
                       line.byteindex(quote, i)
                     else
                       j = i
                       j += 1 while j < bytesize && line.getbyte(j) != quote_byte
                       j < bytesize ? j : nil
                     end
            if next_q.nil?
              i = bytesize # no closing quote — exit loop, return [[], -1] below
              break
            end
            i = next_q # land on the quote; fall through to normal quote-handling below
            b = quote_byte

          # Optimization #12: in :standard mode, once we know the current field is
          # unquoted (field_started && !in_quotes), remaining quotes are literal and
          # cannot affect parser state — jump directly to the next col_sep.
          # Mirrors Opt #10 for the unquoted side of the same trade-off.
          elsif quote_boundary_standard && field_started && !in_quotes
            next_sep = if BYTEINDEX_AVAILABLE
                         line.byteindex(col_sep, i)
                       else
                         j = i
                         j += 1 while j < bytesize && line.getbyte(j) != col_sep_byte
                         j < bytesize ? j : nil
                       end
            if next_sep.nil?
              break
            end

            i = next_sep
            b = col_sep_byte

          else
            b = line.getbyte(i)
          end

          if b == col_sep_byte && !in_quotes
            break if !header_size.nil? && elements.size >= header_size

            field = line.byteslice(start, i - start)
            field = cleanup_quotes(field, quote)
            elements << (strip ? field.strip : field)
            i += 1
            start = i
            backslash_count = 0
            field_started = false # reset for next field
          else
            if allow_escaped_quotes && b == 92 # backslash '\\'
              backslash_count += 1
              field_started = true if quote_boundary_standard && !in_quotes
            else
              if b == quote_byte
                if !allow_escaped_quotes || backslash_count % 2 == 0
                  if quote_boundary_standard
                    if in_quotes
                      # closing quote: only valid if followed by col_sep, row_sep, or end of line
                      next_i = i + 1
                      if next_i >= bytesize ||
                         line.getbyte(next_i) == col_sep_byte ||
                         (row_sep_bytesize > 0 && line.byteslice(next_i, row_sep_bytesize) == row_sep)
                        in_quotes = false
                        field_started = true
                      end
                      # else: quote inside quoted field → literal (handles "" doubling)
                    elsif !field_started # at field boundary: open quoted field
                      in_quotes = true
                      field_started = true
                    end
                    # else: mid-field quote → literal, no state change
                  else
                    in_quotes = !in_quotes
                  end
                end
              elsif quote_boundary_standard && !in_quotes && !field_started
                # Non-quote, non-separator: mark field as started (only needs to fire once
                # per field — Opt #12 skips the rest once this is set).
                # rubocop:disable Style/MultipleComparison -- two direct == comparisons are faster than Array#include? in this hot loop
                field_started = true unless strip && (b == 32 || b == 9) # ' ' == 32, '\t' == 9
                # rubocop:enable Style/MultipleComparison
              end
              backslash_count = 0
            end
            i += 1
          end
        end

        # Unclosed quote at end of line: signal "needs more data" to the caller.
        # The read loop will stitch the next physical line and re-parse rather than raising.
        return [[], -1] if in_quotes

        # Process the remaining field
        if header_size.nil? || elements.size < header_size
          field = line.byteslice(start, bytesize - start)
          field = cleanup_quotes(field, quote)
          elements << (strip ? field.strip : field)
        end
      else
        # Multi-char col_sep: use substring comparison (original path)
        while i < line_size
          # Optimization #10 (multi-char path): same skip-ahead as single-char path above.
          if in_quotes && !allow_escaped_quotes
            next_q = line.index(quote, i)
            if next_q.nil?
              i = line_size
              break
            end
            i = next_q
          end

          # Optimization #12 (multi-char path): mirror of single-char path above.
          if quote_boundary_standard && field_started && !in_quotes
            next_sep = line.index(col_sep, i)
            if next_sep.nil?
              break
            end

            i = next_sep
          end

          if line[i...i+col_sep_size] == col_sep && !in_quotes
            break if !header_size.nil? && elements.size >= header_size

            field = line[start...i]
            field = cleanup_quotes(field, quote)
            elements << (strip ? field.strip : field)
            i += col_sep_size
            start = i
            backslash_count = 0
            field_started = false # reset for next field
          else
            if allow_escaped_quotes && line[i] == '\\'
              backslash_count += 1
              field_started = true if quote_boundary_standard && !in_quotes
            else
              if line[i] == quote
                if !allow_escaped_quotes || backslash_count % 2 == 0
                  if quote_boundary_standard
                    if in_quotes
                      # closing quote: only valid if followed by col_sep, row_sep, or end of line
                      next_i = i + 1
                      if next_i >= line_size ||
                         line[next_i...next_i + col_sep_size] == col_sep ||
                         (row_sep_size > 0 && line[next_i...next_i + row_sep_size] == row_sep)
                        in_quotes = false
                        field_started = true
                      end
                      # else: quote inside quoted field → literal (handles "" doubling)
                    elsif !field_started # at field boundary: open quoted field
                      in_quotes = true
                      field_started = true
                    end
                    # else: mid-field quote → literal, no state change
                  else
                    in_quotes = !in_quotes
                  end
                end
              elsif quote_boundary_standard && !in_quotes && !field_started
                # rubocop:disable Style/MultipleComparison -- two direct == comparisons are faster than Array#include? in this hot loop
                field_started = true unless strip && (line[i] == ' ' || line[i] == '\t')
                # rubocop:enable Style/MultipleComparison
              end
              backslash_count = 0
            end
            i += 1
          end
        end

        # Unclosed quote at end of line: signal "needs more data" to the caller.
        # The read loop will stitch the next physical line and re-parse rather than raising.
        return [[], -1] if in_quotes

        # Process the remaining field
        if header_size.nil? || elements.size < header_size
          field = line[start..-1]
          field = cleanup_quotes(field, quote)
          elements << (strip ? field.strip : field)
        end
      end

      [elements, elements.size]
    end

    def cleanup_quotes(field, quote)
      return nil if field.nil?
      return EMPTY_STRING if field.empty?

      # Remove surrounding quotes if present
      if field.start_with?(quote) && field.end_with?(quote)
        field = field[1..-2]
      end

      # Replace double quotes with a single quote
      field.gsub!(doubled_quote(quote), quote)

      field
    end

    def doubled_quote(quote)
      @doubled_quote ||= (quote * 2).to_s.freeze
    end
  end
end
