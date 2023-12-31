# frozen_string_literal: true

module SmarterCSV
  class << self
    def header_validations(headers, options)
      check_duplicate_headers(headers, options)
      check_required_headers(headers, options)
    end

    def check_duplicate_headers(headers, options)
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
          raise SmarterCSV::MissingKeys, "ERROR: missing attributes: #{missing_keys.join(',')}"
        end
      end
    end

    # def header_validations(headers, options)
    #   duplicate_headers = []
    #   headers.compact.each do |k|
    #     duplicate_headers << k if headers.select{|x| x == k}.size > 1
    #   end

    #   unless duplicate_headers.empty?
    #     raise SmarterCSV::DuplicateHeaders, "ERROR: duplicate headers: #{duplicate_headers.join(',')}"
    #   end

    #   if options[:required_keys] && options[:required_keys].is_a?(Array)
    #     missing_keys = []
    #     options[:required_keys].each do |k|
    #       missing_keys << k unless headers.include?(k)
    #     end
    #     raise SmarterCSV::MissingKeys, "ERROR: missing attributes: #{missing_keys.join(',')}" unless missing_keys.empty?
    #   end
    # end
  end
end
