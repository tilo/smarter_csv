# frozen_string_literal: true

module SmarterCSV
  class << self
    def process_headers(filehandle, options)
      @raw_header = nil # header as it appears in the file
      @headers = nil # the processed headers
      header_array = []
      file_header_size = nil

      # if headers_in_file, get the headers -> We get the number of columns, even when user provided headers
      if options[:headers_in_file] # extract the header line
        # process the header line in the CSV file..
        # the first line of a CSV file contains the header .. it might be commented out, so we need to read it anyhow
        header_line = @raw_header = readline_with_counts(filehandle, options)
        header_line = preprocess_header_line(header_line, options)

        file_header_array, file_header_size = parse(header_line, options)

        # header transformations:
        file_header_array = transform_headers(file_header_array, options)

        # currently this is, but should not be called on user_provided headers
        file_header_array = legacy_header_transformations(file_header_array, options)
      else
        unless options[:user_provided_headers]
          raise SmarterCSV::IncorrectOption, "ERROR: If :headers_in_file is set to false, you have to provide :user_provided_headers"
        end
      end

      if options[:user_provided_headers]
        unless options[:user_provided_headers].is_a?(Array) && !options[:user_provided_headers].empty?
          raise(SmarterCSV::IncorrectOption, "ERROR: incorrect format for user_provided_headers! Expecting array with headers.")
        end

        # use user-provided headers
        user_header_array = options[:user_provided_headers]
        # user_provided_headers: their count should match the headers_in_file if any
        if defined?(file_header_size) && !file_header_size.nil?
          if user_header_array.size != file_header_size
            raise SmarterCSV::HeaderSizeMismatch, "ERROR: :user_provided_headers defines #{user_header_array.size} headers !=  CSV-file has #{file_header_size} headers"
          else
            # we could print out the mapping of file_header_array to header_array here
          end
        end

        header_array = user_header_array

        # these 3 steps should only be part of the header transformation when headers_in_file:
        # -> breaking change when we move this to transform_headers()
        #    see details in legacy_header_transformations()
        #
        header_array = legacy_header_transformations(header_array, options)
      else
        header_array = file_header_array
      end

      validate_headers(header_array, options)

      [header_array, header_array.size]
    end

    private

    def preprocess_header_line(header_line, options)
      header_line = enforce_utf8_encoding(header_line, options)
      header_line = remove_comments_from_header(header_line, options)
      header_line = header_line.chomp(options[:row_sep])
      header_line.gsub!(options[:strip_chars_from_headers], '') if options[:strip_chars_from_headers]
      header_line
    end

    # transform the headers that were in the file:
    def transform_headers(header_array, options)
      header_array.map!{|x| x.gsub(%r/#{options[:quote_char]}/, '')}
      header_array.map!{|x| x.strip} if options[:strip_whitespace]

      unless options[:keep_original_headers]
        header_array.map!{|x| x.gsub(/\s+|-+/, '_')}
        header_array.map!{|x| x.downcase} if options[:downcase_header]
      end

      header_array
    end

    def legacy_header_transformations(header_array, options)
      # detect duplicate headers and disambiguate
      #   -> user_provided_headers should not have duplicates!
      header_array = disambiguate_headers(header_array, options) if options[:duplicate_header_suffix]
      # symbolize headers
      #   -> user_provided_headers should already be symbols or strings as needed
      header_array = header_array.map{|x| x.to_sym } unless options[:strings_as_keys] || options[:keep_original_headers]
      # doesn't make sense to re-map when we have user_provided_headers
      header_array = remap_headers(header_array, options) if options[:key_mapping] && !options[:user_provided_headers]
      header_array
    end

    def disambiguate_headers(headers, options)
      counts = Hash.new(0)
      headers.map do |header|
        counts[header] += 1
        counts[header] > 1 ? "#{header}#{options[:duplicate_header_suffix]}#{counts[header]}" : header
      end
    end

    # do some key mapping on the keys in the file header
    # if you want to completely delete a key, then map it to nil or to ''
    def remap_headers(headers, options)
      key_mapping = options[:key_mapping]
      if key_mapping.empty? || !key_mapping.is_a?(Hash) || key_mapping.keys.empty?
        raise(SmarterCSV::IncorrectOption, "ERROR: incorrect format for key_mapping! Expecting hash with from -> to mappings")
      end

      key_mapping = options[:key_mapping]
      # if silence_missing_keys are not set, raise error if missing header
      missing_keys = key_mapping.keys - headers
      # if the user passes a list of speciffic mapped keys that are optional
      missing_keys -= options[:silence_missing_keys] if options[:silence_missing_keys].is_a?(Array)

      unless missing_keys.empty? || options[:silence_missing_keys] == true
        raise SmarterCSV::KeyMappingError, "ERROR: can not map headers: #{missing_keys.join(', ')}"
      end

      headers.map! do |header|
        if key_mapping.has_key?(header)
          key_mapping[header].nil? ? nil : key_mapping[header]
        elsif options[:remove_unmapped_keys]
          nil
        else
          header
        end
      end
      headers
    end

    # header_validations
    def validate_headers(headers, options)
      duplicate_headers = []
      headers.compact.each do |k|
        duplicate_headers << k if headers.select{|x| x == k}.size > 1
      end

      unless options[:user_provided_headers] || duplicate_headers.empty?
        raise SmarterCSV::DuplicateHeaders, "ERROR: duplicate headers: #{duplicate_headers.join(',')}"
      end

      if options[:required_keys] && options[:required_keys].is_a?(Array)
        missing_keys = []
        options[:required_keys].each do |k|
          missing_keys << k unless headers.include?(k)
        end
        raise SmarterCSV::MissingKeys, "ERROR: missing attributes: #{missing_keys.join(',')}" unless missing_keys.empty?
      end
    end

    def enforce_utf8_encoding(header, options)
      return header unless options[:force_utf8] || options[:file_encoding] !~ /utf-8/i

      header.force_encoding('utf-8').encode('utf-8', invalid: :replace, undef: :replace, replace: options[:invalid_byte_sequence])
    end

    def remove_comments_from_header(header, options)
      return header unless options[:comment_regexp]

      header.sub(options[:comment_regexp], '')
    end
  end
end
