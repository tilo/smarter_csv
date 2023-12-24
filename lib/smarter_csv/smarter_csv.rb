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
    initialize_variables

    options = process_options(given_options)

    has_rails = !!defined?(Rails)

    begin
      fh = input.respond_to?(:readline) ? input : File.open(input, "r:#{options[:file_encoding]}")

      if (options[:force_utf8] || options[:file_encoding] =~ /utf-8/i) && (fh.respond_to?(:external_encoding) && fh.external_encoding != Encoding.find('UTF-8') || fh.respond_to?(:encoding) && fh.encoding != Encoding.find('UTF-8'))
        puts 'WARNING: you are trying to process UTF-8 input, but did not open the input with "b:utf-8" option. See README file "NOTES about File Encodings".'
      end

      # auto-detect the row separator
      options[:row_sep] = guess_line_ending(fh, options) if options[:row_sep]&.to_sym == :auto
      # attempt to auto-detect column separator
      options[:col_sep] = guess_column_separator(fh, options) if options[:col_sep]&.to_sym == :auto

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
      # fh.each_line |line|
      until fh.eof? # we can't use fh.readlines() here, because this would read the whole file into memory at once, and eof => true
        line = readline_with_counts(fh, options)

        # replace invalid byte sequence in UTF-8 with question mark to avoid errors
        line = enforce_utf8_encoding(line, options)

        print "processing file line %10d, csv line %10d\r" % [@file_line_count, @csv_line_count] if options[:verbose]

        next if options[:comment_regexp] && line =~ options[:comment_regexp] # ignore all comment lines if there are any

        # cater for the quoted csv data containing the row separator carriage return character
        # in which case the row data will be split across multiple lines (see the sample content in spec/fixtures/carriage_returns_rn.csv)
        # by detecting the existence of an uneven number of quote characters
        multiline = count_quote_chars(line, options[:quote_char]).odd? # should handle quote_char nil
        while count_quote_chars(line, options[:quote_char]).odd? # should handle quote_char nil
          next_line = fh.readline(options[:row_sep])
          next_line = enforce_utf8_encoding(next_line, options)
          line += next_line
          @file_line_count += 1
        end
        print "\nline contains uneven number of quote chars so including content through file line %d\n" % @file_line_count if options[:verbose] && multiline
        line.chomp!(options[:row_sep])

        # --- SPLIT LINE & DATA TRANSFORMATIONS ------------------------------------------------------------
        dataA, _data_size = parse(line, options, header_size)

        dataA.map!{|x| x.strip} if options[:strip_whitespace]

        # if all values are blank, then ignore this line
        next if options[:remove_empty_hashes] && (dataA.empty? || blank?(dataA))

        # --- HASH TRANSFORMATIONS ------------------------------------------------------------
        hash = @headers.zip(dataA).to_h

        # there may be unmapped keys, or keys purposedly mapped to nil or an empty key..
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
            next if limit_execution_for_only_or_except(options, :convert_values_to_numeric, k)

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

        # --- HASH VALIDATIONS ----------------------------------------------------------------
        # will go here, and be able to:
        #  - validate correct format of the values for fields
        #  - required fields to be non-empty
        #  - ...
        # -------------------------------------------------------------------------------------

        next if options[:remove_empty_hashes] && hash.empty?

        puts "CSV Line #{@file_line_count}: #{pp(hash)}" if options[:verbose] == '2'
        hash[:csv_line_number] = @csv_line_count if options[:with_line_numbers]

        # process the chunks or the resulting hash

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

    # acts as a road-block to limit processing when iterating over all k/v pairs of a CSV-hash:
    def limit_execution_for_only_or_except(options, option_name, key)
      if options[option_name].is_a?(Hash)
        if options[option_name].has_key?(:except)
          return true if Array(options[option_name][:except]).include?(key)
        elsif options[option_name].has_key?(:only)
          return true unless Array(options[option_name][:only]).include?(key)
        end
      end
      false
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

    private

    def enforce_utf8_encoding(line, options)
      return line unless options[:force_utf8] || options[:file_encoding] !~ /utf-8/i

      line.force_encoding('utf-8').encode('utf-8', invalid: :replace, undef: :replace, replace: options[:invalid_byte_sequence])
    end
  end
end
