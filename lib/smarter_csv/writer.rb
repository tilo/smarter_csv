# frozen_string_literal: true

require 'tempfile'

module SmarterCSV
  #
  # Generate CSV files
  #
  # Create an instance of the Writer class with the filename and options.
  # call `<<` one or multiple times to append data to the file.
  # call `finalize` to save the file.
  #
  # The `<<` method can take different arguments:
  #  * a single Hash
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
  #   quote_headers: defaults to false
  #   force_quotes: defaults to false
  #   map_headers: defaults to {}, can be a hash of key -> value mappings
  #   value_converters: optional hash of key -> lambda to control serialization

  # IMPORTANT NOTES:
  #  * Data hashes could contain strings or symbols as keys.
  #    Make sure to use the correct form when specifying headers manually,
  #    in combination with the :discover_headers option

  attr_reader :options, :row_sep, :col_sep, :quote_char, :force_quotes, :discover_headers, :headers, :map_headers, :output_file

  class Writer
    def initialize(file_path, options = {})
      @options = options

      @row_sep = options[:row_sep] || $/
      @col_sep = options[:col_sep] || ','
      @quote_char = options[:quote_char] || '"'
      @force_quotes = options[:force_quotes] == true
      @quote_headers = options[:quote_headers] == true
      @disable_auto_quoting = options[:disable_auto_quoting] == true
      @value_converters = options[:value_converters] || {}
      @map_all_keys = @value_converters.has_key?(:_all)
      @mapped_keys = @value_converters.keys - [:_all]

      @discover_headers = true
      if options.has_key?(:discover_headers)
        @discover_headers = options[:discover_headers] == true
      else
        @discover_headers = !(options.has_key?(:map_headers) || options.has_key?(:headers))
      end

      @headers = []
      @headers = options[:headers] if options.has_key?(:headers)
      @headers = options[:map_headers].keys if options.has_key?(:map_headers) && !options.has_key?(:headers)
      @map_headers = options[:map_headers] || {}

      @output_file = File.open(file_path, 'w+')
      @temp_file = Tempfile.new('tempfile', '/tmp')
      @quote_regex = Regexp.union(@col_sep, @row_sep, @quote_char)
    end

    def <<(data)
      case data
      when Hash
        process_hash(data)
      when Array
        data.each { |item| self << item }
      when NilClass
        # ignore
      else
        # :nocov:
        raise InvalidInputData, "Invalid data type: #{data.class}. Must be a Hash or an Array."
        # :nocov:
      end
    end

    def finalize
      mapped_headers = @headers.map { |header| @map_headers[header] || header }
      force_quotes = @quote_headers || @force_quotes
      mapped_headers = mapped_headers.map { |x| escape_csv_field(x, force_quotes) }

      @temp_file.rewind
      @output_file.write(mapped_headers.join(@col_sep) + @row_sep) unless mapped_headers.empty?
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

      # Reorder the hash to match the current headers order and fill + map missing keys
      ordered_row = @headers.map do |header|
        has_header = hash.key?(header)
        value = has_header ? hash[header] : '' # default to empty value

        # first map individual keys
        value = map_value(header, value) if @mapped_keys.include?(header)

        # then apply general mapping rules
        value = map_all_values(header, value) if @map_all_keys

        escape_csv_field(value, @force_quotes) # for backwards compatibility
      end

      @temp_file.write(ordered_row.join(@col_sep) + @row_sep) unless ordered_row.empty?
    end

    def map_value(key, value)
      @value_converters[key].call(value)
    end

    def map_all_values(key, value)
      @value_converters[:_all].call(key, value)
    end

    def escape_csv_field(field, force_quotes = false)
      str = field.to_s
      return str if @disable_auto_quoting

      # double-quote fields if we force that, or if the field contains the comma, new-line, or quote character
      contains_special_char = str.to_s.match(@quote_regex)
      if force_quotes || contains_special_char
        str = str.gsub(@quote_char, @quote_char * 2) if contains_special_char # escape double-quote

        "\"#{str}\""
      else
        str
      end
    end
  end
end
