# frozen_string_literal: true

module SmarterCSV
  class << self
    def header_validations(headers, options)
      duplicate_headers = []
      headers.compact.each do |k|
        duplicate_headers << k if headers.select{|x| x == k}.size > 1
      end

      unless duplicate_headers.empty?
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
  end
end
