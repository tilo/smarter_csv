# frozen_string_literal: true

module SmarterCSV
  module HashTransformations
    # Frozen regex constants for performance (avoid recompilation on every value)
    NUMERIC_REGEX = /\A[+-]?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?\z/.freeze
    # FLOAT_REGEX = /\A[+-]?\d+\.\d+\z/.freeze
    # INTEGER_REGEX = /\A[+-]?\d+\z/.freeze
    ZERO_REGEX = /\A[+-]?0+(?:\.0+)?\z/.freeze # could be +0.0
    EXPONENT_CHARS = %w[e E].freeze # mantissa scan stops here in significant_digits

    # First-byte values that can begin a numeric literal — used to skip the numeric
    # regexes for values that obviously aren't numbers (e.g. city names).
    ZERO_BYTE  = '0'.ord # 48
    NINE_BYTE  = '9'.ord # 57
    PLUS_BYTE  = '+'.ord # 43
    MINUS_BYTE = '-'.ord # 45

    def hash_transformations(hash, options)
      # Modify hash in-place for performance (avoids allocating a second hash per row)

      # Remove nil/empty keys
      hash.delete(nil)
      hash.delete('')
      hash.delete(:"")

      remove_empty_values = options[:remove_empty_values] == true
      remove_zero_values = options[:remove_zero_values]
      nil_values_matching = options[:nil_values_matching]
      convert_to_numeric = options[:convert_values_to_numeric]
      value_converters = options[:value_converters]

      # Early return if no transformations needed
      return hash unless remove_empty_values || remove_zero_values || nil_values_matching || convert_to_numeric || value_converters

      # {only:}/{except:} limits on numeric conversion apply only when the option is a Hash;
      # in the common case (true/false) skip the per-key check entirely.
      numeric_has_limits = convert_to_numeric.is_a?(Hash)
      rails = has_rails
      keys_to_delete = nil # lazily allocated only if something is actually removed

      hash.each do |k, v|
        # Nil-ify values matching the pattern (keeps the key; remove_empty_values handles deletion)
        if nil_values_matching
          str_val = v.is_a?(String) ? v : (v.is_a?(Numeric) ? v.to_s : nil)
          if str_val && nil_values_matching.match?(str_val)
            hash[k] = nil
            v = nil
            # fall through: remove_empty_values will delete the key if true
          end
        end

        # Check if this key/value should be removed
        # Note: numeric values (Integer/Float) are never blank, so skip the blank check for them
        if remove_empty_values && !v.is_a?(Numeric) && (rails ? v.blank? : blank?(v))
          (keys_to_delete ||= []) << k
          next
        end

        # Handle both string zeros ("0", "0.0") and numeric zeros (already converted by C)
        if remove_zero_values && ((v.is_a?(String) && ZERO_REGEX.match?(v)) || (v.is_a?(Numeric) && v == 0))
          (keys_to_delete ||= []) << k
          next
        end

        # Convert to numeric if requested
        if convert_to_numeric && v.is_a?(String) &&
           (!numeric_has_limits || !limit_execution_for_only_or_except(options, :convert_values_to_numeric, k))
          # Fast-reject: the string is already stripped and NUMERIC_REGEX is \A-anchored on a digit or sign,
          # so a value whose first byte isn't a digit, '+', or '-' cannot be numeric — skip the regex entirely.
          first_byte = v.getbyte(0)
          if first_byte && ((first_byte >= ZERO_BYTE && first_byte <= NINE_BYTE) || first_byte == MINUS_BYTE || first_byte == PLUS_BYTE)
            if NUMERIC_REGEX.match?(v)
              # A value with a '.' or an exponent is a decimal → honor decimal_precision;
              # otherwise it's an integer.
              hash[k] = if v.include?('.') || v.include?('e') || v.include?('E')
                          convert_decimal(v, options[:decimal_precision])
                        else
                          v.to_i
                        end
            end
          end
        end

        # Apply value converters
        if value_converters
          converter = value_converters[k]
          hash[k] = converter.respond_to?(:convert) ? converter.convert(hash[k]) : converter.call(hash[k]) if converter
        end
      end

      # Delete marked keys
      keys_to_delete&.each { |key| hash.delete(key) }

      hash
    end

    # ORIGINAL each_with_object implementation (replaced with in-place modification above)
    # def hash_transformations(hash, options)
    #   remove_empty_values = options[:remove_empty_values] == true
    #   remove_zero_values = options[:remove_zero_values]
    #   nil_values_matching = options[:nil_values_matching]    # replaces deprecated remove_values_matching
    #   convert_to_numeric = options[:convert_values_to_numeric]
    #   value_converters = options[:value_converters]
    #
    #   hash.each_with_object({}) do |(k, v), new_hash|
    #     next if k.nil? || k == '' || k == :""
    #     next if remove_empty_values && (has_rails ? v.blank? : blank?(v))
    #     next if remove_zero_values && v.is_a?(String) && ZERO_REGEX.match?(v)
    #     next if nil_values_matching && nil_values_matching.match?(v)
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

    # Convert a decimal string (has a '.' or an exponent) to a numeric, honoring
    # decimal_precision: :float -> Float, :bigdecimal -> BigDecimal, :auto -> Float unless
    # the value carries more than 16 significant digits (then BigDecimal, no precision loss).
    def convert_decimal(str, decimal_precision)
      case decimal_precision
      when :float
        str.to_f
      when :bigdecimal
        BigDecimal(str)
      else # :auto
        significant_digits(str) > 16 ? BigDecimal(str) : str.to_f
      end
    end

    # Count significant mantissa digits (leading zeros excluded, trailing and fraction
    # digits included, exponent excluded). Matches the C path's fj_sig_digits / Oj's dec_cnt
    # so :auto picks Float vs BigDecimal identically on both paths.
    def significant_digits(str)
      cnt = 0
      started = false
      str.each_char do |c|
        break if EXPONENT_CHARS.include?(c)
        next unless c >= '0' && c <= '9'

        if started
          cnt += 1
        elsif c != '0'
          started = true
          cnt = 1
        end
      end
      cnt
    end

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
