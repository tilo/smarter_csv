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
      @is_io = input.respond_to?(:readline)
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
      # @has_acceleration = !!SmarterCSV::Parser.respond_to?(:parse_csv_line_c)
      @has_acceleration = !!defined?(SmarterCSV::ParserC)
    end

    def process(&block) # rubocop:disable Lint/UnusedMethodArgument
      @enforce_utf8 = options[:force_utf8] || options[:file_encoding] !~ /utf-8/i
      @verbose = options[:verbose]

      begin
        # Perform auto-detection using raw IO
        if options[:row_sep]&.to_sym == :auto || options[:col_sep]&.to_sym == :auto
          io = @is_io ? input : File.open(input, "r:#{options[:file_encoding]}")
          options[:row_sep] = guess_line_ending(io, options) if options[:row_sep]&.to_sym == :auto
          options[:col_sep] = guess_column_separator(io, options) if options[:col_sep]&.to_sym == :auto
          @is_io ? io.rewind : io.close
        end

        # input is either a file-path or an open Ruby IO object
        parser = SmarterCSV::ParserC.new(input, options)
        parser.skip_rows(options[:skip_lines]) if options[:skip_lines].to_i > 0

        # fh = input.respond_to?(:readline) ? input : File.open(input, "r:#{options[:file_encoding]}")

        if (options[:force_utf8] || options[:file_encoding] =~ /utf-8/i) && (input.respond_to?(:external_encoding) && input.external_encoding != Encoding.find('UTF-8') || input.respond_to?(:encoding) && input.encoding != Encoding.find('UTF-8'))
          puts 'WARNING: you are trying to process UTF-8 input, but did not open the input with "b:utf-8" option. See README file "NOTES about File Encodings".'
        end

        # NOTE: we are no longer using header_size
        @headers, _header_size = process_headers(parser, options)
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

        until parser.eof?
          # TO DO:
          #  - COMMENT LINE HANDLING NEEDS TO BE MOVED TO ParserC
###          next if options[:comment_regexp] && line =~ options[:comment_regexp] # ignore all comment lines if there are any

          dataA = parser.read_row_as_fields
          dataA_size = dataA.size
          @file_line_count += 1 # does not make sense anymore
          @csv_line_count += 1

          # replace invalid byte sequence in UTF-8 with question mark to avoid errors
          # line = enforce_utf8_encoding(line, options) if @enforce_utf8

          print "processing CSV row %10d\r" % [@csv_line_count] if @verbose

          # if all values are blank, then ignore this line
          next if options[:remove_empty_hashes] && (dataA.empty? || blank?(dataA))

          # --- SPLIT LINE & DATA TRANSFORMATIONS ------------------------------------------------------------
          # we are now stripping whitespace inside the parse() methods

          if options[:strict] && dataA.size > @headers.size
            raise SmarterCSV::HeaderSizeMismatch, "extra columns detected on line #{@csv_line_count}"
          else
            # we create additional columns on-the-fly
            current_size = @headers.size
            while current_size < dataA_size
              @headers << "#{options[:missing_header_prefix]}#{current_size + 1}".to_sym
              current_size += 1
            end
          end

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
        input.close if input.respond_to?(:close)
      end

      if block_given?
        @chunk_count # when we do processing through a block we only care how many chunks we processed
      else
        @result # returns either an Array of Hashes, or an Array of Arrays of Hashes (if in chunked mode)
      end
    end

    # def count_quote_chars(line, quote_char)
    #   return 0 if line.nil? || quote_char.nil? || quote_char.empty?

    #   count = 0
    #   escaped = false

    #   line.each_char do |char|
    #     if char == '\\' && !escaped
    #       escaped = true
    #     else
    #       count += 1 if char == quote_char && !escaped
    #       escaped = false
    #     end
    #   end

    #   count
    # end

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

    # def enforce_utf8_encoding(line, options)
    #   # return line unless options[:force_utf8] || options[:file_encoding] !~ /utf-8/i

    #   line.force_encoding('utf-8').encode('utf-8', invalid: :replace, undef: :replace, replace: options[:invalid_byte_sequence])
    # end
  end
end
