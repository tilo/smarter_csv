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
      check_duplicate_headers_v1(headers, options)
      check_required_headers_v1(headers, options)
    end

    def check_duplicate_headers_v1(headers, _options)
      header_counts = Hash.new(0)
      headers.each { |header| header_counts[header] += 1 unless header.nil? }

      duplicates = header_counts.select { |_, count| count > 1 }

      unless duplicates.empty?
        raise(SmarterCSV::DuplicateHeaders, "Duplicate Headers in CSV: #{duplicates.inspect}")
      end
    end

    def check_required_headers_v1(headers, options)
      if options[:required_keys] && options[:required_keys].is_a?(Array)
        headers_set = headers.to_set
        missing_keys = options[:required_keys].select { |k| !headers_set.include?(k) }

        unless missing_keys.empty?
          raise SmarterCSV::MissingKeys, "ERROR: missing attributes: #{missing_keys.join(',')}"
        end
      end
    end

    # ---- V2.x Version: validate the headers -----------------------------------------------------------------

    # def header_validations_v2(headers, options)
    #   return unless options[:header_validations]

    #   options[:header_validations].each do |validation|
    #     if validation.respond_to?(:call)
    #       # Directly call if it's a Proc or lambda
    #       validation.call(headers)
    #     else
    #       binding.pry
    #       # Handle Symbol, Hash, or Array
    #       method_name, args = validation.is_a?(Symbol) ? [validation, []] : validation
    #       public_send(method_name, headers, *Array(args))
    #     end
    #   end
    # end

    def header_validations_v2(headers, options)
      return unless options[:header_validations]

      # do the header validations the user requested:
      # Header validations typically raise errors directly
      #
      options[:header_validations].each do |validation|
        if validation.respond_to?(:call)
          # Directly call if it's a Proc or lambda
          validation.call(headers)
        else
          case validation
          when Symbol
            public_send(validation, headers)
          when Hash
            val, args = validation.first
            public_send(val, headers, args)
          when Array
            val, *args = validation
            public_send(val, headers, args)
          else
            raise SmarterCSV::IncorrectOption, "Invalid validation type: #{validation.class}"
          end
        end
      end
    end

    # def header_validations_v2_orig(headers, options)
    #   # do the header validations the user requested:
    #   # Header validations typically raise errors directly
    #   #
    #   if options[:header_validations]
    #     options[:header_validations].each do |validation|
    #       case validation
    #       when Symbol
    #         public_send(validation, headers)
    #       when Hash
    #         val, args = validation.first
    #         public_send(val, headers, args)
    #       when Array
    #         val, args = validation
    #         public_send(val, headers, args)
    #       else
    #         validation.call(headers) unless validation.nil?
    #       end
    #     end
    #   end
    # end

    # these are some pre-defined header validations which can be used
    # all these take the headers array as the input
    #
    # the computed options can be accessed via @options

    def unique_headers(headers)
      header_counts = Hash.new(0)
      headers.each { |header| header_counts[header] += 1 unless header.nil? }

      duplicates = header_counts.select { |_, count| count > 1 }

      unless duplicates.empty?
        raise(SmarterCSV::DuplicateHeaders, "Duplicate Headers in CSV: #{duplicates.inspect}")
      end
    end

    def required_headers(headers, required = [])
      raise(SmarterCSV::IncorrectOption, "ERROR: required_headers validation needs an array argument") unless required.is_a?(Array)

      headers_set = headers.to_set
      missing = required.select { |r| !headers_set.include?(r) }

      unless missing.empty?
        raise(SmarterCSV::MissingKeys, "Missing Headers in CSV: #{missing.inspect}")
      end
    end
  end
end
