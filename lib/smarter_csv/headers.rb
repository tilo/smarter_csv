# frozen_string_literal: true

module SmarterCSV
  class << self
    def process_headers(filehandle, options)
      @raw_header = nil # header as it appears in the file
      @headers = nil
      headerA = []

      if options[:headers_in_file] # extract the header line
        # process the header line in the CSV file..
        # the first line of a CSV file contains the header .. it might be commented out, so we need to read it anyhow
        header = readline_with_counts(filehandle, options)
        @raw_header = header

        header = header.force_encoding('utf-8').encode('utf-8', invalid: :replace, undef: :replace, replace: options[:invalid_byte_sequence]) if options[:force_utf8] || options[:file_encoding] !~ /utf-8/i
        header = header.sub(options[:comment_regexp], '') if options[:comment_regexp]
        header = header.chomp(options[:row_sep])

        header = header.gsub(options[:strip_chars_from_headers], '') if options[:strip_chars_from_headers]

        file_headerA, file_header_size = parse(header, options)

        file_headerA.map!{|x| x.gsub(%r/#{options[:quote_char]}/, '')}
        file_headerA.map!{|x| x.strip} if options[:strip_whitespace]

        unless options[:keep_original_headers]
          file_headerA.map!{|x| x.gsub(/\s+|-+/, '_')}
          file_headerA.map!{|x| x.downcase} if options[:downcase_header]
        end
      else
        unless options[:user_provided_headers]
          raise SmarterCSV::IncorrectOption, "ERROR: If :headers_in_file is set to false, you have to provide :user_provided_headers"
        end
      end

      if options[:user_provided_headers] && options[:user_provided_headers].class == Array && !options[:user_provided_headers].empty?
        # use user-provided headers
        headerA = options[:user_provided_headers]
        if defined?(file_header_size) && !file_header_size.nil?
          if headerA.size != file_header_size
            raise SmarterCSV::HeaderSizeMismatch, "ERROR: :user_provided_headers defines #{headerA.size} headers !=  CSV-file has #{file_header_size} headers"
          else
            # we could print out the mapping of file_headerA to headerA here
          end
        end
      else
        # raise  SmarterCSV::IncorrectOption, "ERROR: WTF!"
        headerA = file_headerA
      end

      # detect duplicate headers and disambiguate
      headerA = process_duplicate_headers(headerA, options) if options[:duplicate_header_suffix]
      header_size = headerA.size # used for splitting lines

      headerA.map!{|x| x.to_sym } unless options[:strings_as_keys] || options[:keep_original_headers]

      unless options[:user_provided_headers] # wouldn't make sense to re-map user provided headers
        key_mappingH = options[:key_mapping]

        # do some key mapping on the keys in the file header
        #   if you want to completely delete a key, then map it to nil or to ''
        if !key_mappingH.nil? && key_mappingH.class == Hash && key_mappingH.keys.size > 0
          # if silence_missing_keys are not set, raise error if missing header
          missing_keys = key_mappingH.keys - headerA
          # if the user passes a list of speciffic mapped keys that are optional
          missing_keys -= options[:silence_missing_keys] if options[:silence_missing_keys].is_a?(Array)

          unless missing_keys.empty? || options[:silence_missing_keys] == true
            raise SmarterCSV::KeyMappingError, "ERROR: can not map headers: #{missing_keys.join(', ')}"
          end

          headerA.map!{|x| key_mappingH.has_key?(x) ? (key_mappingH[x].nil? ? nil : key_mappingH[x]) : (options[:remove_unmapped_keys] ? nil : x)}
        end
      end

      # header_validations
      duplicate_headers = []
      headerA.compact.each do |k|
        duplicate_headers << k if headerA.select{|x| x == k}.size > 1
      end

      unless options[:user_provided_headers] || duplicate_headers.empty?
        raise SmarterCSV::DuplicateHeaders, "ERROR: duplicate headers: #{duplicate_headers.join(',')}"
      end

      # deprecate required_headers
      unless options[:required_headers].nil?
        puts "DEPRECATION WARNING: please use 'required_keys' instead of 'required_headers'"
        if options[:required_keys].nil?
          options[:required_keys] = options[:required_headers]
          options[:required_headers] = nil
        end
      end

      if options[:required_keys] && options[:required_keys].is_a?(Array)
        missing_keys = []
        options[:required_keys].each do |k|
          missing_keys << k unless headerA.include?(k)
        end
        raise SmarterCSV::MissingKeys, "ERROR: missing attributes: #{missing_keys.join(',')}" unless missing_keys.empty?
      end

      [headerA, header_size]
    end

    def process_duplicate_headers(headers, options)
      counts = Hash.new(0)
      result = []
      headers.each do |key|
        counts[key] += 1
        if counts[key] == 1
          result << key
        else
          result << [key, options[:duplicate_header_suffix], counts[key]].join
        end
      end
      result
    end
  end
end
