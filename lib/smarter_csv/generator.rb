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
  class Generator
    def initialize(file_path, options = {})
      @options = options
      @headers = options[:headers] || []
      @col_sep = options[:col_sep] || ','
      @force_quotes = options[:force_quotes]
      @map_headers = options[:map_headers] || {}
      @file = File.open(file_path, 'w+')
    end

    def append(array_of_hashes)
      array_of_hashes.each do |hash|
        hash_keys = hash.keys
        new_keys = hash_keys - @headers
        @headers.concat(new_keys)

        # Reorder the hash to match the current headers order and fill missing fields
        ordered_row = @headers.map { |header| hash[header] || '' }

        @file.puts ordered_row.map { |value| escape_csv_field(value) }.join(@col_sep)
      end
    end

    def finalize
      # Map headers if :map_headers option is provided
      mapped_headers = @headers.map { |header| @map_headers[header] || header }

      # Rewind to the beginning of the file to write the headers
      @file.rewind
      @file.write(mapped_headers.join(@col_sep) + "\n")
      @file.flush # Ensure all data is written to the file
      @file.close
    end

    private

    def escape_csv_field(field)
      if @force_quotes || field.to_s.include?(@col_sep)
        "\"#{field}\""
      else
        field.to_s
      end
    end
  end
end
