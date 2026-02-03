# frozen_string_literal: true

module SmarterCSV
  module HashTransformations
    # Frozen regex constants for performance (avoid recompilation on every value)
    FLOAT_REGEX = /\A[+-]?\d+\.\d+\z/.freeze
    INTEGER_REGEX = /\A[+-]?\d+\z/.freeze
    ZERO_REGEX = /\A0+(?:\.0+)?\z/.freeze

    def hash_transformations(hash, options)
      # Modify hash in-place for performance (avoids allocating a second hash per row)

      # Remove nil/empty keys
      hash.delete(nil)
      hash.delete('')
      hash.delete(:"")

      remove_empty_values = options[:remove_empty_values] == true
      remove_zero_values = options[:remove_zero_values]
      remove_values_matching = options[:remove_values_matching]
      convert_to_numeric = options[:convert_values_to_numeric]
      value_converters = options[:value_converters]

      # Early return if no transformations needed
      return hash unless remove_empty_values || remove_zero_values || remove_values_matching || convert_to_numeric || value_converters

      keys_to_delete = []

      hash.each do |k, v|
        # Check if this key/value should be removed
        if remove_empty_values && (has_rails ? v.blank? : blank?(v))
          keys_to_delete << k
          next
        end

        if remove_zero_values && v.is_a?(String) && ZERO_REGEX.match?(v)
          keys_to_delete << k
          next
        end

        if remove_values_matching && v.is_a?(String) && remove_values_matching.match?(v)
          keys_to_delete << k
          next
        end

        # Convert to numeric if requested
        if convert_to_numeric && v.is_a?(String) && !limit_execution_for_only_or_except(options, :convert_values_to_numeric, k)
          if FLOAT_REGEX.match?(v)
            hash[k] = v.to_f
          elsif INTEGER_REGEX.match?(v)
            hash[k] = v.to_i
          end
        end

        # Apply value converters
        if value_converters
          converter = value_converters[k]
          hash[k] = converter.convert(hash[k]) if converter
        end
      end

      # Delete marked keys
      keys_to_delete.each { |k| hash.delete(k) }

      hash
    end

    # ORIGINAL each_with_object implementation (replaced with in-place modification above)
    # def hash_transformations(hash, options)
    #   remove_empty_values = options[:remove_empty_values] == true
    #   remove_zero_values = options[:remove_zero_values]
    #   remove_values_matching = options[:remove_values_matching]
    #   convert_to_numeric = options[:convert_values_to_numeric]
    #   value_converters = options[:value_converters]
    #
    #   hash.each_with_object({}) do |(k, v), new_hash|
    #     next if k.nil? || k == '' || k == :""
    #     next if remove_empty_values && (has_rails ? v.blank? : blank?(v))
    #     next if remove_zero_values && v.is_a?(String) && ZERO_REGEX.match?(v)
    #     next if remove_values_matching && remove_values_matching.match?(v)
    #
    #     if convert_to_numeric && !limit_execution_for_only_or_except(options, :convert_values_to_numeric, k)
    #       if v.is_a?(String)
    #         if FLOAT_REGEX.match?(v)
    #           v = v.to_f
    #         elsif INTEGER_REGEX.match?(v)
    #           v = v.to_i
    #         end
    #       end
    #     end
    #
    #     converter = value_converters[k] if value_converters
    #     v = converter.convert(v) if converter
    #
    #     new_hash[k] = v
    #   end
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
