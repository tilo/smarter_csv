# frozen_string_literal: true

module SmarterCSV
  class Reader
    include ::SmarterCSV::Options
    include ::SmarterCSV::FileIO
    include ::SmarterCSV::AutoDetection
    include ::SmarterCSV::Headers
    include ::SmarterCSV::HeaderTransformations
    include ::SmarterCSV::HeaderValidations
    include ::SmarterCSV::HashTransformations
    include ::SmarterCSV::Parser

    attr_reader :input, :options
    attr_reader :csv_line_count, :chunk_count, :file_line_count
    attr_reader :enforce_utf8, :has_rails, :has_acceleration
    attr_reader :errors, :warnings, :headers, :raw_header, :result

    # :nocov:
    # rubocop:disable Naming/MethodName
    def headerA
      warn "Deprecarion Warning: 'headerA' will be removed in future versions. Use 'headders'"
      @headerA
    end
    # rubocop:enable Naming/MethodName
    # :nocov:

    # first parameter: filename or input object which responds to readline method
    def initialize(input, given_options = {})
      @input = input
      @has_rails = !!defined?(Rails)
      @csv_line_count = 0
      @chunk_count = 0
      @errors = {}
      @file_line_count = 0
      @headerA = []
      @headers = nil
      @raw_header = nil # header as it appears in the file
      @result = []
      @warnings = {}
      @enforce_utf8 = false # only set to true if needed (after options parsing)
      @options = process_options(given_options)
      # true if it is compiled with accelleration
      @has_acceleration = !!SmarterCSV::Parser.respond_to?(:parse_csv_line_c)
    end

    def process(&block) # rubocop:disable Lint/UnusedMethodArgument
      @enforce_utf8 = options[:force_utf8] || options[:file_encoding] !~ /utf-8/i
      @verbose = options[:verbose]

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

        puts "Effective headers:\n#{pp(@headers)}\n" if @verbose

        header_validations(@headers, options)

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
          line = enforce_utf8_encoding(line, options) if @enforce_utf8

          print "processing file line %10d, csv line %10d\r" % [@file_line_count, @csv_line_count] if @verbose

          next if options[:comment_regexp] && line =~ options[:comment_regexp] # ignore all comment lines if there are any

          # cater for the quoted csv data containing the row separator carriage return character
          # in which case the row data will be split across multiple lines (see the sample content in spec/fixtures/carriage_returns_rn.csv)
          # by detecting the existence of an uneven number of quote characters
          multiline = count_quote_chars(line, options[:quote_char]).odd?

          while multiline
            next_line = fh.readline(options[:row_sep])
            next_line = enforce_utf8_encoding(next_line, options) if @enforce_utf8
            line += next_line
            @file_line_count += 1

            break if fh.eof? # Exit loop if end of file is reached

            multiline = count_quote_chars(line, options[:quote_char]).odd?
          end

          # :nocov:
          if multiline && @verbose
            print "\nline contains uneven number of quote chars so including content through file line %d\n" % @file_line_count
          end
          # :nocov:

          line.chomp!(options[:row_sep])

          # --- SPLIT LINE & DATA TRANSFORMATIONS ------------------------------------------------------------
          dataA, _data_size = parse(line, options, header_size)

          dataA.map!{|x| x.strip} if options[:strip_whitespace]

          # if all values are blank, then ignore this line
          next if options[:remove_empty_hashes] && (dataA.empty? || blank?(dataA))

          # --- HASH TRANSFORMATIONS ------------------------------------------------------------
          hash = @headers.zip(dataA).to_h

          hash = hash_transformations(hash, options)

          # --- HASH VALIDATIONS ----------------------------------------------------------------
          # will go here, and be able to:
          #  - validate correct format of the values for fields
          #  - required fields to be non-empty
          #  - ...
          # -------------------------------------------------------------------------------------

          next if options[:remove_empty_hashes] && hash.empty?

          puts "CSV Line #{@file_line_count}: #{pp(hash)}" if @verbose == '2' # very verbose setting
          # optional adding of csv_line_number to the hash to help debugging
          hash[:csv_line_number] = @csv_line_count if options[:with_line_numbers]

          # process the chunks or the resulting hash
          if use_chunks
            chunk << hash # append temp result to chunk

            if chunk.size >= chunk_size || fh.eof? # if chunk if full, or EOF reached
              # do something with the chunk
              if block_given?
                yield chunk # do something with the hashes in the chunk in the block
              else
                @result << chunk.dup # Append chunk to result (use .dup to keep a copy after we do chunk.clear)
              end
              @chunk_count += 1
              chunk.clear # re-initialize for next chunk of data
            else
              # the last chunk may contain partial data, which is handled below
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
        print "\n" if @verbose

        # handling of last chunk:
        if !chunk.nil? && chunk.size > 0
          # do something with the chunk
          if block_given?
            yield chunk # do something with the hashes in the chunk in the block
          else
            @result << chunk.dup # Append chunk to result (use .dup to keep a copy after we do chunk.clear)
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

    def count_quote_chars(line, quote_char)
      return 0 if line.nil? || quote_char.nil? || quote_char.empty?

      count = 0
      escaped = false

      line.each_char do |char|
        if char == '\\' && !escaped
          escaped = true
        else
          count += 1 if char == quote_char && !escaped
          escaped = false
        end
      end

      count
    end

    protected

    # SEE: https://github.com/rails/rails/blob/32015b6f369adc839c4f0955f2d9dce50c0b6123/activesupport/lib/active_support/core_ext/object/blank.rb#L121
    # and in the future we might also include UTF-8 space characters: https://www.compart.com/en/unicode/category/Zs
    BLANK_RE = /\A\s*\z/.freeze

    def blank?(value)
      case value
      when String
        BLANK_RE.match?(value)
      when NilClass
        true
      when Array
        value.all? { |elem| blank?(elem) }
      when Hash
        value.values.all? { |elem| blank?(elem) } # Focus on values only
      else
        false
      end
    end

    private

    def enforce_utf8_encoding(line, options)
      # return line unless options[:force_utf8] || options[:file_encoding] !~ /utf-8/i

      line.force_encoding('utf-8').encode('utf-8', invalid: :replace, undef: :replace, replace: options[:invalid_byte_sequence])
    end
  end
end
