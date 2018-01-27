module SmarterCSV
  # these are some pre-defined data hash transformations which can be used
  # all these take the data hash as the input
  #
  # the computed options can be accessed via @options

  def self.strip_spaces(hash, args=nil)
    @@strip_spaces ||= Proc.new {|hash, args=nil|
      keys = (args.nil? || args.empty?) ? hash.keys : ( args.is_a?(Array) ? args : [ args ] )

      keys.each {|key| hash[key]&.strip! }
      hash
    }
    @@strip_spaces.call(hash)
  end

  def self.remove_blank_values(hash, args=nil)
    @@remove_blank_values ||= Proc.new {|hash, args=nil|
      keys = (args.nil? || args.empty?) ? hash.keys : ( args.is_a?(Array) ? args : [ args ] )

      keys.each {|key| hash.delete(key) if hash[key].nil? || hash[key].is_a?(String) && hash[key] !~ /[^[:space:]]/ }
      hash
    }
    @@remove_blank_values.call(hash)
  end

  def self.remove_zero_values(hash, args=nil)
    @@remove_zero_values ||= Proc.new {|hash, args=nil|
      keys = (args.nil? || args.empty?) ? hash.keys : ( args.is_a?(Array) ? args : [ args ] )

      keys.each {|key| hash.delete(key) if hash[key].is_a?(Numeric) && hash[key].zero? }
      hash
    }
    @@remove_zero_values.call(hash)
  end

  def self.convert_values_to_numeric(hash, args=nil)
    @@convert_values_to_numeric ||= Proc.new {|hash, args=nil|
      keys = (args.nil? || args.empty?) ? hash.keys : ( args.is_a?(Array) ? args : [ args ] )

      keys.each {|k|
        case hash[k]
        when /^[+-]?\d+\.\d+$/
          hash[k] = hash[k].to_f
        when /^[+-]?\d+$/
          hash[k] = hash[k].to_i
        end
      }
      hash
    }
    @@convert_values_to_numeric.call(hash)
  end

  def self.convert_values_to_numeric_unless_leading_zeroes(hash, args=nil)
    @@convert_values_to_numeric_unless_leading_zeroes ||= Proc.new {|hash, args=nil|
      keys = (args.nil? || args.empty?) ? hash.keys : ( args.is_a?(Array) ? args : [ args ] )

      keys.each {|k|
        case hash[k]
        when /^[+-]?[1-9]\d*\.\d+$/
          hash[k] = hash[k].to_f
        when /^[+-]?[1-9]\d*$/
          hash[k] = hash[k].to_i
        end
      }
      hash
    }
    @@convert_values_to_numeric_unless_leading_zeroes.call(hash)
  end

  # IMPORTANT NOTE:
  # this can lead to cases where a nil or empty value gets converted into 0 or 0.0,
  # and can then not be properly removed!
  #
  # you should first try to use convert_values_to_numeric or convert_values_to_numeric_unless_leading_zeroes
  #
  def self.convert_to_integer(hash, args=nil)
    @@convert_to_integer ||= Proc.new{|hash, args=nil|
      keys = (args.nil? || args.empty?) ? hash.keys : ( args.is_a?(Array) ? args : [ args ] )

      keys.each {|key| hash[key] = hash[key].to_i }
      hash
    }
    @@convert_to_integer.call(hash, args)
  end

  def self.convert_to_float(hash, args=nil)
    @@convert_to_integer ||= Proc.new{|hash, args=nil|
      keys = (args.nil? || args.empty?) ? hash.keys : ( args.is_a?(Array) ? args : [ args ] )

      keys.each {|key| hash[key] = hash[key].to_f }
      hash
    }
    @@convert_to_float.call(hash, args)
  end

end
