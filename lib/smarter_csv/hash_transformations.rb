# frozen_string_literal: true

module SmarterCSV
  class << self
    # this is processing the headers from the input file
    def hash_transformations(hash, options)
      if options[:v2_mode]
        hash_transformations_v2(hash, options)
      else
        hash_transformations_v1(hash, options)
      end
    end

    def hash_transformations_v1(hash, options)
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

    def hash_transformations_v2(hash, options)
      return hash if options[:hash_transformations].nil? || options[:hash_transformations].empty?

      # do the header transformations the user requested:
      if options[:hash_transformations]
        options[:hash_transformations].each do |transformation|
          if transformation.respond_to?(:call) # this is used when a user-provided Proc is passed in
            hash = transformation.call(hash, options)
          else
            case transformation
            when Symbol # this is used for pre-defined transformations that are defined in the SmarterCSV module
              hash = public_send(transformation, hash, options)
            when Hash # this is called for hash arguments, e.g. hash_transformations
              trans, args = transformation.first # .first treats the hash first element as an array
              hash = apply_transformation(trans, hash, args, options)
            when Array # this can be used for passing additional arguments in array form (e.g. into a Proc)
              trans, *args = transformation
              hash = apply_transformation(trans, hash, args, options)
            else
              raise SmarterCSV::IncorrectOption, "Invalid transformation type: #{transformation.class}"
            end
          end
        end
      end

      hash
    end

    #
    # To handle v1-backward-compatible behavior, it is faster to roll all behavior into one method
    #
    def v1_backwards_compatibility(hash, options)
      hash.each_with_object({}) do |(k, v), new_hash|
        next if k.nil? || k == '' || k == :"" # remove_empty_keys
        next if has_rails ? v.blank? : blank?(v) # remove_empty_values

        # convert_values_to_numeric:
        # deal with the :only / :except options to :convert_values_to_numeric
        unless limit_execution_for_only_or_except(options, :convert_values_to_numeric, k)
          if v =~ /^[+-]?\d+\.\d+$/
            v = v.to_f
          elsif v =~ /^[+-]?\d+$/
            v = v.to_i
          end
        end

        new_hash[k] = v
      end
    end

    #
    # Building Blocks in case you want to build your own flow:
    #
    def strip_spaces(hash, _options)
      hash.each_key {|key| hash[key].strip! unless hash[key].nil? } # &. syntax was introduced in Ruby 2.3 - need to stay backwards compatible
    end

    def remove_blank_values(hash, _options)
      hash.each_key {|key| hash.delete(key) if hash[key].nil? || hash[key].is_a?(String) && hash[key] !~ /[^[:space:]]/ }
    end

    def remove_zero_values(hash, _options)
      hash.each_key {|key| hash.delete(key) if hash[key].is_a?(Numeric) && hash[key].zero? }
    end

    def remove_empty_keys(hash, _options)
      hash.reject!{|key, _v| key.nil? || key.empty?}
    end

    def convert_values_to_numeric(hash, _options)
      hash.each_key do |k|
        case hash[k]
        when /^[+-]?\d+\.\d+$/
          hash[k] = hash[k].to_f
        when /^[+-]?\d+$/
          hash[k] = hash[k].to_i
        end
      end
    end

    def convert_values_to_numeric_unless_leading_zeroes(hash, _options)
      hash.each_key do |k|
        case hash[k]
        when /^[+-]?[1-9]\d*\.\d+$/
          hash[k] = hash[k].to_f
        when /^[+-]?[1-9]\d*$/
          hash[k] = hash[k].to_i
        end
      end
    end

    # IMPORTANT NOTE:
    # this can lead to cases where a nil or empty value gets converted into 0 or 0.0,
    # and can then not be properly removed!
    #
    # you should first try to use convert_values_to_numeric or convert_values_to_numeric_unless_leading_zeroes
    #
    def convert_to_integer(hash, _options)
      hash.each_key {|key| hash[key] = hash[key].to_i }
    end

    def convert_to_float(hash, _options)
      hash.each_key {|key| hash[key] = hash[key].to_f }
    end

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
