module SmarterCSV
  # these are some pre-defined header validations which can be used
  # all these take the headers array as the input

  def self.enforce_unique_headers(array)
    @@unique_headers ||= Proc.new {|headers|
      dupes = headers.each_with_object({}){|x,h| h[x] ||= 0; h[x] += 1}.reject{|k,v| v < 2}
      dupes.empty? ? nil : "Duplicate Headers in CSV: #{dupes.inspect}"
    }
    @@unique_headers.call(array)
  end

  def self.check_required_headers(array,required=[])
    @@required_headers ||= Proc.new {|headers, required=[]|
      missing = required.each_with_object([]){|x,a| a << x unless headers.include?(x)}
      missing.empty? ? nil : "Missing Headers in CSV: #{missing.inspect}"
    }
    @@required_headers.call(array,required)
  end

end
