# frozen_string_literal: true

module SmarterCSV
  #
  # Generate CSV files from batches of array_of_hashes data
  # - automatically generates the header on-the-fly
  # - automatically quotes fields containing the col_sep
  #
  # Optionally headers can be passed-in via the options,
  # If any new headers are fund in the data, they will be appended to the headers.
  #
  class Writer
    def initialize(file_path, options = {})
      @options = options
      @discover_headers = options.has_key?(:discover_headers) ? (options[:discover_headers] == true) : true
      @headers = options[:headers] || []
      @row_sep = options[:row_sep] || "\n" # RFC4180 "\r\n"
      @col_sep = options[:col_sep] || ','
      @quote_char = '"'
      @force_quotes = options[:force_quotes]
      @map_headers = options[:map_headers] || {}
      @temp_file = Tempfile.new('tempfile', '/tmp')
      @output_file = File.open(file_path, 'w+')
      @quote_regex = Regexp.union(@col_sep, @row_sep, @quote_char)
    end

    def append(array_of_hashes)
      array_of_hashes.each do |hash|
        hash_keys = hash.keys
        new_keys = hash_keys - @headers
        @headers.concat(new_keys)

        # Reorder the hash to match the current headers order and fill missing fields
        ordered_row = @headers.map { |header| hash[header] || '' }

        @temp_file.write ordered_row.map { |value| escape_csv_field(value) }.join(@col_sep) + @row_sep
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
    end

    private

    def escape_csv_field(field)
      if @force_quotes || field.to_s.match(@quote_regex)
        "\"#{field}\""
      else
        field.to_s
      end
    end
  end
end
