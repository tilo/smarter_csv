# frozen_string_literal: true

module SmarterCSV
  #
  # Generate CSV files
  #
  # Create an instance of the Writer class with the filename and options.
  # call `<<` one or mulltiple times to append data to the file.
  # call `finalize` to save the file.
  #
  # The `<<` method can take different arguments:
  #  * a signle Hash
  #  * an array of Hashes
  #  * nested arrays of arrays of Hashes
  #
  # By default SmarterCSV::Writer automatically discovers all headers that are present
  # in the data on-the-fly. This can be disabled, then only given headers are used.
  # Disabling can be useful when you want to select attributes from hashes, or ActiveRecord instances.
  #
  # If `discover_headers` is enabled, and headers are given, any new headers that are found in the data will still be appended.
  #
  # The Writer automatically quotes fields containing the col_sep, row_sep, or the quote_char.
  #
  # Options:
  #   col_sep : defaults to , but can be set to any other character
  #   row_sep : defaults to LF \n , but can be set to \r\n or \r or anything else
  #   quote_char : defaults to "
  #   discover_headers : defaults to true
  #   headers : defaults to []
  #   force_quotes: defaults to false
  #   map_headers: defaults to {}, can be a hash of key -> value mappings

  # IMPORTANT NOTES:
  #  * Data hashes could contain strings or symbols as keys.
  #    Make sure to use the correct form when specifying headers manually,
  #    in combination with the :discover_headers option

  attr_reader :options, :row_sep, :col_sep, :quote_char, :force_quotes, :discover_headers, :headers, :map_headers, :output_file

  class Writer
    def initialize(file_path, options = {})
      @options = options

      @row_sep = options[:row_sep] || $/ # Defaults to system's row separator. RFC4180 "\r\n"
      @col_sep = options[:col_sep] || ','
      @quote_char = options[:quote_char] || '"'
      @force_quotes = options[:force_quotes] == true
      @discover_headers = true # defaults to true
      if options.has_key?(:discover_headers)
        # passing in the option overrides the default behavior
        @discover_headers = options[:discover_headers] == true
      else
        # disable discover_headers when headers are given explicitly
        @discover_headers = !(options.has_key?(:map_headers) || options.has_key?(:headers))
      end
      @headers = [] # start with empty headers
      @headers = options[:headers] if options.has_key?(:headers) # unless explicitly given
      @headers = options[:map_headers].keys if options.has_key?(:map_headers) && !options.has_key?(:headers)
      @map_headers = options[:map_headers] || {}

      @output_file = File.open(file_path, 'w+')
      # hidden state:
      @temp_file = Tempfile.new('tempfile', '/tmp')
      @quote_regex = Regexp.union(@col_sep, @row_sep, @quote_char)
    end

    # this can be called many times in order to append lines to the csv file
    def <<(data)
      case data
      when Hash
        process_hash(data)
      when Array
        data.each { |item| self << item }
      when NilClass
        # ignore
      else
        raise InvalidInputData, "Invalid data type: #{data.class}. Must be a Hash or an Array."
      end
    end

    def finalize
      # Map headers if :map_headers option is provided
      mapped_headers = @headers.map { |header| @map_headers[header] || header }

      @temp_file.rewind
      @output_file.write(mapped_headers.join(@col_sep) + @row_sep)
      @output_file.write(@temp_file.read)
      @output_file.flush
      @output_file.close
      @temp_file.delete
    end

    private

    def process_hash(hash)
      if @discover_headers
        hash_keys = hash.keys
        new_keys = hash_keys - @headers
        @headers.concat(new_keys)
      end

      # Reorder the hash to match the current headers order and fill missing fields
      ordered_row = @headers.map { |header| hash[header] || '' }

      @temp_file.write ordered_row.map { |value| escape_csv_field(value) }.join(@col_sep) + @row_sep
    end

    def escape_csv_field(field)
      if @force_quotes || field.to_s.match(@quote_regex)
        "\"#{field}\""
      else
        field.to_s
      end
    end
  end
end
