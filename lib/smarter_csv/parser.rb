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
          backslash_options = options.merge(quote_escaping: :backslash)
          parse_csv_line_ruby(line, backslash_options, header_size, has_quotes)
        end
      rescue MalformedCSV
        # Backslash interpretation failed — fall back to RFC 4180
        if options[:acceleration] && has_acceleration
          # :nocov:
          elements = parse_csv_line_c(line, options[:col_sep], options[:quote_char], header_size, has_quotes, options[:strip_whitespace], false)
          [elements, elements.size]
          # :nocov:
        else
          rfc_options = options.merge(quote_escaping: :double_quotes)
          parse_csv_line_ruby(line, rfc_options, header_size, has_quotes)
        end
      end
    end

    # Parse a CSV line directly into a hash, with support for extra columns.
    # Returns [hash_or_nil, data_size] where hash is nil if all values are blank.
    def parse_line_to_hash(line, headers, options)
      if options[:quote_escaping] == :auto
        parse_line_to_hash_auto(line, headers, options)
      else
        has_quotes = line.include?(options[:quote_char])

        if options[:acceleration] && has_acceleration
          # :nocov:
          parse_line_to_hash_c(
            line,
            headers,
            options[:col_sep],
            options[:quote_char],
            options[:missing_header_prefix],
            has_quotes,
            options[:strip_whitespace],
            options[:remove_empty_hashes],
            options[:remove_empty_values],
            options[:quote_escaping] == :backslash
          )
          # :nocov:
        else
          parse_line_to_hash_ruby(line, headers, options, has_quotes)
        end
      end
    end

    def parse_line_to_hash_auto(line, headers, options)
      has_quotes = line.include?(options[:quote_char])

      begin
        # Try backslash-escape interpretation first
        if options[:acceleration] && has_acceleration
          # :nocov:
          parse_line_to_hash_c(
            line, headers, options[:col_sep], options[:quote_char],
            options[:missing_header_prefix], has_quotes, options[:strip_whitespace],
            options[:remove_empty_hashes], options[:remove_empty_values], true
          )
          # :nocov:
        else
          backslash_options = options.merge(quote_escaping: :backslash)
          parse_line_to_hash_ruby(line, headers, backslash_options, has_quotes)
        end
      rescue MalformedCSV
        # Backslash interpretation failed — fall back to RFC 4180
        if options[:acceleration] && has_acceleration
          # :nocov:
          parse_line_to_hash_c(
            line, headers, options[:col_sep], options[:quote_char],
            options[:missing_header_prefix], has_quotes, options[:strip_whitespace],
            options[:remove_empty_hashes], options[:remove_empty_values], false
          )
          # :nocov:
        else
          rfc_options = options.merge(quote_escaping: :double_quotes)
          parse_line_to_hash_ruby(line, headers, rfc_options, has_quotes)
        end
      end
    end

    # Ruby implementation of parse_line_to_hash
    def parse_line_to_hash_ruby(line, headers, options, has_quotes = false)
      return [nil, 0] if line.nil?

      # Parse the line into values
      elements, data_size = parse_csv_line_ruby(line, options, nil, has_quotes)

      # Check if all values are blank
      if options[:remove_empty_hashes] && (elements.empty? || elements.all? { |v| v.nil? || v.to_s.strip.empty? })
        return [nil, data_size]
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

    def parse_csv_line_ruby(line, options, header_size = nil, _has_quotes = false)
      return [[], 0] if line.nil?

      line_size = line.size
      col_sep = options[:col_sep]
      col_sep_size = col_sep.size
      quote = options[:quote_char]
      elements = []
      start = 0
      i = 0

      backslash_count = 0
      in_quotes = false
      allow_escaped_quotes = options[:quote_escaping] == :backslash

      while i < line_size
        # Check if the current position matches the column separator and we're not inside quotes
        if line[i...i+col_sep_size] == col_sep && !in_quotes
          break if !header_size.nil? && elements.size >= header_size

          elements << cleanup_quotes(line[start...i], quote)
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

      # Check for unclosed quotes at the end of the line
      if in_quotes
        # :nocov:
        raise MalformedCSV, "Unclosed quoted field detected in line: #{line}"
        # :nocov:
      end

      # Process the remaining field
      if header_size.nil? || elements.size < header_size
        elements << cleanup_quotes(line[start..-1], quote)
      end

      elements.map!(&:strip) if options[:strip_whitespace]
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
