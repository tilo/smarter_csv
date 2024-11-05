# frozen_string_literal: true

module SmarterCSV
  module Parser
    protected

    ###
    ### Thin wrapper around C-extension
    ###
    ### NOTE: we are no longer passing-in header_size
    ###
    def parse(line, options, header_size = nil)
      # puts "SmarterCSV.parse OPTIONS: #{options[:acceleration]}" if options[:verbose]

      if options[:acceleration] && has_acceleration
        # :nocov:
        has_quotes = line =~ /#{options[:quote_char]}/
        elements = parse_csv_line_c(line, options[:col_sep], options[:quote_char], header_size)
        elements.map!{|x| cleanup_quotes(x, options[:quote_char])} if has_quotes
        [elements, elements.size]
        # :nocov:
      else
        # puts "WARNING: SmarterCSV is using un-accelerated parsing of lines. Check options[:acceleration]"
        parse_csv_line_ruby(line, options, header_size)
      end
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

    def parse_csv_line_ruby(line, options, header_size = nil)
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

      while i < line_size
        # Check if the current position matches the column separator and we're not inside quotes
        if line[i...i+col_sep_size] == col_sep && !in_quotes
          break if !header_size.nil? && elements.size >= header_size

          elements << cleanup_quotes(line[start...i], quote)
          i += col_sep_size
          start = i
          backslash_count = 0 # Reset backslash count at the start of a new field
        else
          if line[i] == '\\'
            backslash_count += 1
          else
            if line[i] == quote
              if backslash_count % 2 == 0
                # Even number of backslashes means quote is not escaped
                in_quotes = !in_quotes
              end
              # Else, quote is escaped; do nothing
            end
            backslash_count = 0 # Reset after any character other than backslash
          end
          i += 1
        end
      end

      # Check for unclosed quotes at the end of the line
      if in_quotes
        raise MalformedCSV, "Unclosed quoted field detected in line: #{line}"
      end

      # Process the remaining field
      if header_size.nil? || elements.size < header_size
        elements << cleanup_quotes(line[start..-1], quote)
      end

      [elements, elements.size]
    end

    def cleanup_quotes(field, quote)
      return field if field.nil?

      # Remove surrounding quotes if present
      if field.start_with?(quote) && field.end_with?(quote)
        field = field[1..-2]
      end

      # Replace double quotes with a single quote
      field.gsub!("#{quote * 2}", quote)

      field
    end
  end
end
