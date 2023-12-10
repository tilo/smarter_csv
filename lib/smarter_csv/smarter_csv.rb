# frozen_string_literal: true

module SmarterCSV
  class SmarterCSVException < StandardError; end
  class HeaderSizeMismatch < SmarterCSVException; end
  class IncorrectOption < SmarterCSVException; end
  class ValidationError < SmarterCSVException; end
  class DuplicateHeaders < SmarterCSVException; end
  class MissingKeys < SmarterCSVException; end # previously known as MissingHeaders
  class NoColSepDetected < SmarterCSVException; end
  class KeyMappingError < SmarterCSVException; end

  # first parameter: filename or input object which responds to readline method
  def SmarterCSV.process(input, given_options = {}, &block) # rubocop:disable Lint/UnusedMethodArgument
    options = process_options(given_options)

    initialize_variables

    has_rails = !!defined?(Rails)
    begin
      fh = input.respond_to?(:readline) ? input : File.open(input, "r:#{options[:file_encoding]}")

      # auto-detect the row separator
      options[:row_sep] = guess_line_ending(fh, options) if options[:row_sep]&.to_sym == :auto
      # attempt to auto-detect column separator
      options[:col_sep] = guess_column_separator(fh, options) if options[:col_sep]&.to_sym == :auto

      if (options[:force_utf8] || options[:file_encoding] =~ /utf-8/i) && (fh.respond_to?(:external_encoding) && fh.external_encoding != Encoding.find('UTF-8') || fh.respond_to?(:encoding) && fh.encoding != Encoding.find('UTF-8'))
        puts 'WARNING: you are trying to process UTF-8 input, but did not open the input with "b:utf-8" option. See README file "NOTES about File Encodings".'
      end

      skip_lines(fh, options)

      @headers, header_size = process_headers(fh, options)
      @headerA = @headers # @headerA is deprecated, use @headers

      # in case we use chunking.. we'll need to set it up..
      if options[:chunk_size].to_i > 0
        use_chunks = true
        chunk_size = options[:chunk_size].to_i
        @chunk_count = 0
        chunk = []
      else
        use_chunks = false
      end

      # now on to processing all the rest of the lines in the CSV file:
      until fh.eof? # we can't use fh.readlines() here, because this would read the whole file into memory at once, and eof => true
        line = readline_with_counts(fh, options)

        # replace invalid byte sequence in UTF-8 with question mark to avoid errors
        line = line.force_encoding('utf-8').encode('utf-8', invalid: :replace, undef: :replace, replace: options[:invalid_byte_sequence]) if options[:force_utf8] || options[:file_encoding] !~ /utf-8/i

        print "processing file line %10d, csv line %10d\r" % [@file_line_count, @csv_line_count] if options[:verbose]

        next if options[:comment_regexp] && line =~ options[:comment_regexp] # ignore all comment lines if there are any

        # cater for the quoted csv data containing the row separator carriage return character
        # in which case the row data will be split across multiple lines (see the sample content in spec/fixtures/carriage_returns_rn.csv)
        # by detecting the existence of an uneven number of quote characters

        multiline = count_quote_chars(line, options[:quote_char]).odd? # should handle quote_char nil
        while count_quote_chars(line, options[:quote_char]).odd? # should handle quote_char nil
          next_line = fh.readline(options[:row_sep])
          next_line = next_line.force_encoding('utf-8').encode('utf-8', invalid: :replace, undef: :replace, replace: options[:invalid_byte_sequence]) if options[:force_utf8] || options[:file_encoding] !~ /utf-8/i
          line += next_line
          @file_line_count += 1
        end
        print "\nline contains uneven number of quote chars so including content through file line %d\n" % @file_line_count if options[:verbose] && multiline

        line.chomp!(options[:row_sep])

        dataA, _data_size = parse(line, options, header_size)

        dataA.map!{|x| x.strip} if options[:strip_whitespace]

        # if all values are blank, then ignore this line
        next if options[:remove_empty_hashes] && (dataA.empty? || blank?(dataA))

        hash = Hash.zip(@headers, dataA) # from Facets of Ruby library

        # make sure we delete any key/value pairs from the hash, which the user wanted to delete:
        hash.delete(nil)
        hash.delete('')
        hash.delete(:"")

        if options[:remove_empty_values] == true
          hash.delete_if{|_k, v| has_rails ? v.blank? : blank?(v)}
        end

        hash.delete_if{|_k, v| !v.nil? && v =~ /^(0+|0+\.0+)$/} if options[:remove_zero_values] # values are Strings
        hash.delete_if{|_k, v| v =~ options[:remove_values_matching]} if options[:remove_values_matching]

        if options[:convert_values_to_numeric]
          hash.each do |k, v|
            # deal with the :only / :except options to :convert_values_to_numeric
            next if only_or_except_limit_execution(options, :convert_values_to_numeric, k)

            # convert if it's a numeric value:
            case v
            when /^[+-]?\d+\.\d+$/
              hash[k] = v.to_f
            when /^[+-]?\d+$/
              hash[k] = v.to_i
            end
          end
        end

        if options[:value_converters]
          hash.each do |k, v|
            converter = options[:value_converters][k]
            next unless converter

            hash[k] = converter.convert(v)
          end
        end

        next if options[:remove_empty_hashes] && hash.empty?

        hash[:csv_line_number] = @csv_line_count if options[:with_line_numbers]

        if use_chunks
          chunk << hash # append temp result to chunk

          if chunk.size >= chunk_size || fh.eof? # if chunk if full, or EOF reached
            # do something with the chunk
            if block_given?
              yield chunk # do something with the hashes in the chunk in the block
            else
              @result << chunk # not sure yet, why anybody would want to do this without a block
            end
            @chunk_count += 1
            chunk = [] # initialize for next chunk of data
          else

            # the last chunk may contain partial data, which also needs to be returned (BUG / ISSUE-18)

          end

          # while a chunk is being filled up we don't need to do anything else here

        else # no chunk handling
          if block_given?
            yield [hash] # do something with the hash in the block (better to use chunking here)
          else
            @result << hash
          end
        end
      end

      # print new line to retain last processing line message
      print "\n" if options[:verbose]

      # last chunk:
      if !chunk.nil? && chunk.size > 0
        # do something with the chunk
        if block_given?
          yield chunk # do something with the hashes in the chunk in the block
        else
          @result << chunk # not sure yet, why anybody would want to do this without a block
        end
        @chunk_count += 1
        # chunk = [] # initialize for next chunk of data
      end
    ensure
      fh.close if fh.respond_to?(:close)
    end
    if block_given?
      @chunk_count # when we do processing through a block we only care how many chunks we processed
    else
      @result # returns either an Array of Hashes, or an Array of Arrays of Hashes (if in chunked mode)
    end
  end

  class << self
    # * the `scan` method iterates through the string and finds all occurrences of the pattern
    # * The reqular expression:
    #   - (?<!\\) : Negative lookbehind to ensure the quote character is not preceded by an unescaped backslash.
    #   - (?:\\\\)* : Non-capturing group for an even number of backslashes (escaped backslashes).
    #                 This allows for any number of escaped backslashes before the quote character.
    #   - #{Regexp.escape(quote_char)} : Dynamically inserts the quote_char into the regex,
    #                                    ensuring it's properly escaped for use in the regex.
    #
    def count_quote_chars(line, quote_char)
      line.scan(/(?<!\\)(?:\\\\)*#{Regexp.escape(quote_char)}/).count
    end

    def has_acceleration?
      @has_acceleration ||= !!defined?(parse_csv_line_c)
    end

    protected

    ###
    ### Thin wrapper around C-extension
    ###
    def parse(line, options, header_size = nil)
      # puts "SmarterCSV.parse OPTIONS: #{options[:acceleration]}" if options[:verbose]

      if options[:acceleration] && has_acceleration?
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

    def readline_with_counts(filehandle, options)
      line = filehandle.readline(options[:row_sep])
      @file_line_count += 1
      @csv_line_count += 1
      line = remove_bom(line) if @csv_line_count == 1
      line
    end

    def skip_lines(filehandle, options)
      options[:skip_lines].to_i.times do
        readline_with_counts(filehandle, options)
      end
    end

    def rewind(filehandle)
      @file_line_count = 0
      @csv_line_count = 0
      filehandle.rewind
    end

    # SEE: https://github.com/rails/rails/blob/32015b6f369adc839c4f0955f2d9dce50c0b6123/activesupport/lib/active_support/core_ext/object/blank.rb#L121
    # and in the future we might also include UTF-8 space characters: https://www.compart.com/en/unicode/category/Zs
    BLANK_RE = /\A\s*\z/.freeze

    def blank?(value)
      case value
      when String
        value.empty? || BLANK_RE.match?(value)

      when NilClass
        true

      when Array
        value.empty? || value.inject(true){|result, x| result && elem_blank?(x)}

      when Hash
        value.empty? || value.values.inject(true){|result, x| result && elem_blank?(x)}

      else
        false
      end
    end

    def elem_blank?(value)
      case value
      when String
        value.empty? || BLANK_RE.match?(value)

      when NilClass
        true

      else
        false
      end
    end

    # acts as a road-block to limit processing when iterating over all k/v pairs of a CSV-hash:
    def only_or_except_limit_execution(options, option_name, key)
      if options[option_name].is_a?(Hash)
        if options[option_name].has_key?(:except)
          return true if Array(options[option_name][:except]).include?(key)
        elsif options[option_name].has_key?(:only)
          return true unless Array(options[option_name][:only]).include?(key)
        end
      end
      false
    end

    # If file has headers, then guesses column separator from headers.
    # Otherwise guesses column separator from contents.
    # Raises exception if none is found.
    def guess_column_separator(filehandle, options)
      skip_lines(filehandle, options)

      delimiters = [',', "\t", ';', ':', '|']

      line = nil
      has_header = options[:headers_in_file]
      candidates = Hash.new(0)
      count = has_header ? 1 : 5
      count.times do
        line = readline_with_counts(filehandle, options)
        delimiters.each do |d|
          candidates[d] += line.scan(d).count
        end
      rescue EOFError # short files
        break
      end
      rewind(filehandle)

      if candidates.values.max == 0
        # if the header only contains
        return ',' if line.chomp(options[:row_sep]) =~ /^\w+$/

        raise SmarterCSV::NoColSepDetected
      end

      candidates.key(candidates.values.max)
    end

    # limitation: this currently reads the whole file in before making a decision
    def guess_line_ending(filehandle, options)
      counts = {"\n" => 0, "\r" => 0, "\r\n" => 0}
      quoted_char = false

      # count how many of the pre-defined line-endings we find
      # ignoring those contained within quote characters
      last_char = nil
      lines = 0
      filehandle.each_char do |c|
        quoted_char = !quoted_char if c == options[:quote_char]
        next if quoted_char

        if last_char == "\r"
          if c == "\n"
            counts["\r\n"] += 1
          else
            counts["\r"] += 1 # \r are counted after they appeared
          end
        elsif c == "\n"
          counts["\n"] += 1
        end
        last_char = c
        lines += 1
        break if options[:auto_row_sep_chars] && options[:auto_row_sep_chars] > 0 && lines >= options[:auto_row_sep_chars]
      end
      rewind(filehandle)

      counts["\r"] += 1 if last_char == "\r"
      # find the most frequent key/value pair:
      most_frequent_key, _count = counts.max_by{|_, v| v}
      most_frequent_key
    end

    private

    UTF_32_BOM = %w[0 0 fe ff].freeze
    UTF_32LE_BOM = %w[ff fe 0 0].freeze
    UTF_8_BOM = %w[ef bb bf].freeze
    UTF_16_BOM = %w[fe ff].freeze
    UTF_16LE_BOM = %w[ff fe].freeze

    def remove_bom(str)
      str_as_hex = str.bytes.map{|x| x.to_s(16)}
      # if string does not start with one of the bytes, there is no BOM
      return str unless %w[ef fe ff 0].include?(str_as_hex[0])

      return str.byteslice(4..-1) if [UTF_32_BOM, UTF_32LE_BOM].include?(str_as_hex[0..3])
      return str.byteslice(3..-1) if str_as_hex[0..2] == UTF_8_BOM
      return str.byteslice(2..-1) if [UTF_16_BOM, UTF_16LE_BOM].include?(str_as_hex[0..1])

      # :nocov:
      puts "SmarterCSV found unhandled BOM! #{str.chars[0..7].inspect}"
      str
      # :nocov:
    end
  end
end
