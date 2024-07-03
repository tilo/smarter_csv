# frozen_string_literal: true

module SmarterCSV
  module HashTransformations
    def hash_transformations(hash, options)
      # there may be unmapped keys, or keys purposedly mapped to nil or an empty key..
      # make sure we delete any key/value pairs from the hash, which the user wanted to delete:
      remove_empty_values = options[:remove_empty_values] == true
      remove_zero_values = options[:remove_zero_values]
      remove_values_matching = options[:remove_values_matching]
      convert_to_numeric = options[:convert_values_to_numeric]
      value_converters = options[:value_converters]

      hash.each_with_object({}) do |(k, v), new_hash|
        next if k.nil? || k == '' || k == :""
        next if remove_empty_values && (has_rails ? v.blank? : blank?(v))
        next if remove_zero_values && v.is_a?(String) && v =~ /^(0+|0+\.0+)$/ # values are Strings
        next if remove_values_matching && v =~ remove_values_matching

        # deal with the :only / :except options to :convert_values_to_numeric
        if convert_to_numeric && !limit_execution_for_only_or_except(options, :convert_values_to_numeric, k)
          if v =~ /^[+-]?\d+\.\d+$/
            v = v.to_f
          elsif v =~ /^[+-]?\d+$/
            v = v.to_i
          end
        end

        converter = value_converters[k] if value_converters
        v = converter.convert(v) if converter

        new_hash[k] = v
      end
    end

    # def hash_transformations(hash, options)
    #   # there may be unmapped keys, or keys purposedly mapped to nil or an empty key..
    #   # make sure we delete any key/value pairs from the hash, which the user wanted to delete:
    #   hash.delete(nil)
    #   hash.delete('')
    #   hash.delete(:"")

    #   if options[:remove_empty_values] == true
    #     hash.delete_if{|_k, v| has_rails ? v.blank? : blank?(v)}
    #   end

    #   hash.delete_if{|_k, v| !v.nil? && v =~ /^(0+|0+\.0+)$/} if options[:remove_zero_values] # values are Strings
    #   hash.delete_if{|_k, v| v =~ options[:remove_values_matching]} if options[:remove_values_matching]

    #   if options[:convert_values_to_numeric]
    #     hash.each do |k, v|
    #       # deal with the :only / :except options to :convert_values_to_numeric
    #       next if limit_execution_for_only_or_except(options, :convert_values_to_numeric, k)

    #       # convert if it's a numeric value:
    #       case v
    #       when /^[+-]?\d+\.\d+$/
    #         hash[k] = v.to_f
    #       when /^[+-]?\d+$/
    #         hash[k] = v.to_i
    #       end
    #     end
    #   end

    #   if options[:value_converters]
    #     hash.each do |k, v|
    #       converter = options[:value_converters][k]
    #       next unless converter

    #       hash[k] = converter.convert(v)
    #     end
    #   end

    #   hash
    # end

    protected

    # acts as a road-block to limit processing when iterating over all k/v pairs of a CSV-hash:
    def limit_execution_for_only_or_except(options, option_name, key)
      if options[option_name].is_a?(Hash)
        if options[option_name].has_key?(:except)
          return true if Array(options[option_name][:except]).include?(key)
        elsif options[option_name].has_key?(:only)
          return true unless Array(options[option_name][:only]).include?(key)
        end
      end
      false
    end
  end
end
