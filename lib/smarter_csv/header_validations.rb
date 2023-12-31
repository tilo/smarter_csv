# frozen_string_literal: true

module SmarterCSV
  class << self
    def header_validations(headers, options)
      if options[:v2_mode]
        header_validations_v2(headers, options)
      else
        header_validations_v1(headers, options)
      end
    end

    # ---- V1.x Version: validate the headers -----------------------------------------------------------------

    def header_validations_v1(headers, options)
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

    # ---- V2.x Version: validate the headers -----------------------------------------------------------------

    def header_validations_v2(headers, options)
      # do the header validations the user requested:
      # Header validations typically raise errors directly
      #
      if options[:header_validations]
        options[:header_validations].each do |validation|
          case validation
          when Symbol
            public_send(validation, headers)
          when Hash
            val, args = validation.first
            public_send(val, headers, args)
          when Array
            val, args = validation
            public_send(val, headers, args)
          else
            validation.call(headers) unless validation.nil?
          end
        end
      end
    end

    # these are some pre-defined header validations which can be used
    # all these take the headers array as the input
    #
    # the computed options can be accessed via @options

    @unique_headers = nil

    def unique_headers(array)
      @unique_headers ||= proc {|headers|
        dupes = headers.each_with_object({}) do |x, h|
          # when we remove fields we map them to nil - we don't count these as dupes
          h[x] ||= 0
          h[x] += 1
        end.reject do |k, v|
          k.nil? || v < 2
        end
        dupes.empty? ? nil : raise(SmarterCSV::DuplicateHeaders, "Duplicate Headers in CSV: #{dupes.inspect}")
      }
      @unique_headers.call(array)
    end

    @required_headers = nil

    def required_headers(array, required = [])
      @required_headers ||= proc {|headers, required = []|
        raise(SmarterCSV::IncorrectOption, "ERROR: required_headers validation needs an array argument") unless required.is_a?(Array)

        missing = required.each_with_object([]){ |x, a| a << x unless headers.include?(x) }
        missing.empty? ? nil : raise(SmarterCSV::MissingHeaders, "Missing Headers in CSV: #{missing.inspect}")
      }
      @required_headers.call(array, required)
    end
  end
end
