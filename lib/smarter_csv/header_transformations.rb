# frozen_string_literal: true

module SmarterCSV
  module HeaderTransformations
    # transform the headers that were in the file:
    def header_transformations(header_array, options)
      header_array.map!{|x| x.gsub(%r/#{options[:quote_char]}/, '')}
      header_array.map!{|x| x.strip} if options[:strip_whitespace]

      unless options[:keep_original_headers]
        header_array.map!{|x| x.gsub(/\s+|-+/, '_')}
        header_array.map!{|x| x.downcase} if options[:downcase_header]
      end

      # detect duplicate headers and disambiguate
      header_array = disambiguate_headers(header_array, options) if options[:duplicate_header_suffix]
      # symbolize headers
      header_array = header_array.map{|x| x.to_sym } unless options[:strings_as_keys] || options[:keep_original_headers]
      # doesn't make sense to re-map when we have user_provided_headers
      header_array = remap_headers(header_array, options) if options[:key_mapping]

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
  end
end
