# the following extension for class Array is needed if using an old version of ruby I.e, 2.0.0)

class Array

  def to_h
    if RUBY_VERSION.to_f < 2.1
      hash = {}
      each_with_index do |item, index|
        if item.is_a?(Array) 
          raise ArgumentError, "wrong array length at #{index} (expected 2, was #{item.length})" unless item.length == 2
          hash[item[0]] = item[1]
        else
          raise TypeError, "wrong element type #{item.class} at #{index} (expected array)"
        end
      end
      hash
    else
      super
    end
  end

end
