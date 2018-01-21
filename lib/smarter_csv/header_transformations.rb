module SmarterCSV
  # these are some pre-defined header transformations which can be used
  # all these take the headers array as the input

  def self.keys_as_symbols(array)
    @@keys_as_symbols ||= Proc.new {|headers|
      headers.map{|x| x.strip.downcase.gsub(/(\s|\-)+/,'_').to_sym }
    }
    @@keys_as_symbols.call(array)
  end

  def self.keys_as_strings(array)
    @@keys_as_strings ||= Proc.new {|headers|
      headers.map{|x| x.strip.downcase.gsub(/(\s|\-)+/,'_') }
    }
    @@keys_as_strings.call(array)
  end

end
