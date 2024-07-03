# frozen_string_literal: true

module SmarterCSV
  module HeaderValidations
    def header_validations(headers, options)
      check_duplicate_headers(headers, options)
      check_required_headers(headers, options)
    end

    def check_duplicate_headers(headers, _options)
      header_counts = Hash.new(0)
      headers.each { |header| header_counts[header] += 1 unless header.nil? }

      duplicates = header_counts.select { |_, count| count > 1 }

      unless duplicates.empty?
        raise(SmarterCSV::DuplicateHeaders, "Duplicate Headers in CSV: #{duplicates.inspect}")
      end
    end

    require 'set'

    def check_required_headers(headers, options)
      if options[:required_keys] && options[:required_keys].is_a?(Array)
        headers_set = headers.to_set
        missing_keys = options[:required_keys].select { |k| !headers_set.include?(k) }

        unless missing_keys.empty?
          raise SmarterCSV::MissingKeys, "ERROR: missing attributes: #{missing_keys.join(',')}. Check `reader.headers` for original headers."
        end
      end
    end
  end
end
