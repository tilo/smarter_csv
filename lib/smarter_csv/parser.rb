# frozen_string_literal: true

module SmarterCSV
  module Parser
    EMPTY_STRING = '' # already frozen

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
          elements = parse_csv_line_c(line, options[:col_sep], options[:quote_char], header_size, has_quotes, options[:strip_whitespace], options[:quote_escaping] == :backslash)
          [elements, elements.size]
          # :nocov:
        else
          # puts "WARNING: SmarterCSV is using un-accelerated parsing of lines. Check options[:acceleration]"
          parse_csv_line_ruby(line, options, header_size, has_quotes)
        end
      end
    end

    def parse_with_auto_fallback(line, options, header_size = nil)
      has_quotes = line.include?(options[:quote_char])

      begin
        # Try backslash-escape interpretation first
        if options[:acceleration] && has_acceleration
          # :nocov:
          elements = parse_csv_line_c(line, options[:col_sep], options[:quote_char], header_size, has_quotes, options[:strip_whitespace], true)
          [elements, elements.size]
          # :nocov:
        else
          # Optimization #4: cache merged options hashes for :auto mode
          @backslash_options ||= options.merge(quote_escaping: :backslash)
          parse_csv_line_ruby(line, @backslash_options, header_size, has_quotes)
        end
      rescue MalformedCSV
        # Backslash interpretation failed — fall back to RFC 4180
        if options[:acceleration] && has_acceleration
          # :nocov:
          elements = parse_csv_line_c(line, options[:col_sep], options[:quote_char], header_size, has_quotes, options[:strip_whitespace], false)
          [elements, elements.size]
          # :nocov:
        else
          # Optimization #4: cache merged options hashes for :auto mode
          @rfc_options ||= options.merge(quote_escaping: :double_quotes)
          parse_csv_line_ruby(line, @rfc_options, header_size, has_quotes)
        end
      end
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
      begin
        # Try backslash-escape interpretation first
        if options[:acceleration] && has_acceleration
          # :nocov:
          # Optimization #4: cache merged options hashes for :auto mode
          @backslash_options ||= options.merge(quote_escaping: :backslash)
          parse_line_to_hash_c(line, headers, @backslash_options)
          # :nocov:
        else
          has_quotes = line.include?(options[:quote_char])
          # Optimization #4: cache merged options hashes for :auto mode
          @backslash_options ||= options.merge(quote_escaping: :backslash)
          parse_line_to_hash_ruby(line, headers, @backslash_options, has_quotes)
        end
      rescue MalformedCSV
        # Backslash interpretation failed — fall back to RFC 4180
        if options[:acceleration] && has_acceleration
          # :nocov:
          # Optimization #4: cache merged options hashes for :auto mode
          @rfc_options ||= options.merge(quote_escaping: :double_quotes)
          parse_line_to_hash_c(line, headers, @rfc_options)
          # :nocov:
        else
          has_quotes = line.include?(options[:quote_char])
          # Optimization #4: cache merged options hashes for :auto mode
          @rfc_options ||= options.merge(quote_escaping: :double_quotes)
          parse_line_to_hash_ruby(line, headers, @rfc_options, has_quotes)
        end
      end
    end

    # Ruby implementation of parse_line_to_hash
    def parse_line_to_hash_ruby(line, headers, options, has_quotes = false)
      return [nil, 0] if line.nil?

      # Chomp trailing row separator
      line = line.chomp(options[:row_sep]) if options[:row_sep]

      # Parse the line into values
      elements, data_size = parse_csv_line_ruby(line, options, nil, has_quotes)

      # Optimization #6: elements are always String or nil from parse_csv_line_ruby,
      # so .to_s is unnecessary. If strip_whitespace is on, fields are already
      # stripped, so .strip is also redundant — just check .empty?.
      if options[:remove_empty_hashes]
        all_blank = if options[:strip_whitespace]
                      elements.empty? || elements.all? { |v| v.nil? || v.empty? }
                    else
                      elements.empty? || elements.all? { |v| v.nil? || v.strip.empty? }
                    end
        return [nil, data_size] if all_blank
      end

      # Build the hash - only include keys for values that exist
      hash = {}
      elements.each_with_index do |value, i|
        key = if i < headers.size
                headers[i]
              else
                "#{options[:missing_header_prefix]}#{i + 1}".to_sym
              end
        hash[key] = value
      end

      # Add nil for missing columns only when remove_empty_values is false
      # (when true, nils would be removed anyway by hash_transformations)
      unless options[:remove_empty_values]
        (elements.size...headers.size).each do |i|
          hash[headers[i]] = nil
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
      has_quotes = line.include?(options[:quote_char]) unless has_quotes

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

      # Optimization #1: for the common single-char separator, use direct
      # character comparison instead of allocating a substring via line[i...i+n].
      if col_sep_size == 1
        while i < line_size
          if line[i] == col_sep && !in_quotes
            break if !header_size.nil? && elements.size >= header_size

            field = line[start...i]
            field = cleanup_quotes(field, quote)
            elements << (strip ? field.strip : field)
            i += 1
            start = i
            backslash_count = 0
          else
            if allow_escaped_quotes && line[i] == '\\'
              backslash_count += 1
            else
              if line[i] == quote
                if !allow_escaped_quotes || backslash_count % 2 == 0
                  in_quotes = !in_quotes
                end
              end
              backslash_count = 0
            end
            i += 1
          end
        end
      else
        # Multi-char col_sep: use substring comparison (original path)
        while i < line_size
          if line[i...i+col_sep_size] == col_sep && !in_quotes
            break if !header_size.nil? && elements.size >= header_size

            field = line[start...i]
            field = cleanup_quotes(field, quote)
            elements << (strip ? field.strip : field)
            i += col_sep_size
            start = i
            backslash_count = 0
          else
            if allow_escaped_quotes && line[i] == '\\'
              backslash_count += 1
            else
              if line[i] == quote
                if !allow_escaped_quotes || backslash_count % 2 == 0
                  in_quotes = !in_quotes
                end
              end
              backslash_count = 0
            end
            i += 1
          end
        end
      end

      # Check for unclosed quotes at the end of the line
      if in_quotes
        # :nocov:
        raise MalformedCSV, "Unclosed quoted field detected in line: #{line}"
        # :nocov:
      end

      # Process the remaining field
      if header_size.nil? || elements.size < header_size
        field = line[start..-1]
        field = cleanup_quotes(field, quote)
        elements << (strip ? field.strip : field)
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
