# frozen_string_literal: true

module SmarterCSV
  module Parser
    protected

    ###
    ### Thin wrapper around C-extension
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
    # - if header_size is given, only up to header_size fields are parsed
    #
    # We use header_size for parsing the body lines to make sure we always match the number of headers
    # in case there are trailing col_sep characters in line
    #
    # Our convention is that empty fields are returned as empty strings, not as nil.
    #
    #
    # the purpose of the max_size parameter is to handle a corner case where
    # CSV lines contain more fields than the header.
    # In which case the remaining fields in the line are ignored
    #
    def parse_csv_line_ruby(line, options, header_size = nil)
      return [] if line.nil?

      line_size = line.size
      col_sep = options[:col_sep]
      col_sep_size = col_sep.size
      quote = options[:quote_char]
      quote_count = 0
      elements = []
      start = 0
      i = 0

      previous_char = ''
      while i < line_size
        if line[i...i+col_sep_size] == col_sep && quote_count.even?
          break if !header_size.nil? && elements.size >= header_size

          elements << cleanup_quotes(line[start...i], quote)
          previous_char = line[i]
          i += col_sep.size
          start = i
        else
          quote_count += 1 if line[i] == quote && previous_char != '\\'
          previous_char = line[i]
          i += 1
        end
      end
      elements << cleanup_quotes(line[start..-1], quote) if header_size.nil? || elements.size < header_size
      [elements, elements.size]
    end

    def cleanup_quotes(field, quote)
      return field if field.nil?

      # return if field !~ /#{quote}/ # this check can probably eliminated

      if field.start_with?(quote) && field.end_with?(quote)
        field.delete_prefix!(quote)
        field.delete_suffix!(quote)
      end
      field.gsub!("#{quote}#{quote}", quote)
      field
    end
  end
end
