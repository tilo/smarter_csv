# frozen_string_literal: true

module SmarterCSV
  class << self
    def hash_transformations(hash, options)
      # there may be unmapped keys, or keys purposedly mapped to nil or an empty key..
      # make sure we delete any key/value pairs from the hash, which the user wanted to delete:
      hash.delete(nil)
      hash.delete('')
      hash.delete(:"")

      if options[:remove_empty_values] == true
        hash.delete_if{|_k, v| has_rails ? v.blank? : blank?(v)}
      end

      hash.delete_if{|_k, v| !v.nil? && v =~ /^(0+|0+\.0+)$/} if options[:remove_zero_values] # values are Strings
      hash.delete_if{|_k, v| v =~ options[:remove_values_matching]} if options[:remove_values_matching]

      if options[:convert_values_to_numeric]
        hash.each do |k, v|
          # deal with the :only / :except options to :convert_values_to_numeric
          next if limit_execution_for_only_or_except(options, :convert_values_to_numeric, k)

          # convert if it's a numeric value:
          case v
          when /^[+-]?\d+\.\d+$/
            hash[k] = v.to_f
          when /^[+-]?\d+$/
            hash[k] = v.to_i
          end
        end
      end

      if options[:value_converters]
        hash.each do |k, v|
          converter = options[:value_converters][k]
          next unless converter

          hash[k] = converter.convert(v)
        end
      end

      hash
    end
  end
end
