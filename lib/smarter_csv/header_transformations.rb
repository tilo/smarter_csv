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

  # this is a convenience function for supporting v1 feature parity

  def self.key_mapping(array, mapping={})
    @@key_mapping ||= Proc.new {|headers,mapping={}|
      raise( SmarterCSV::IncorrectOption , "ERROR: key_mapping header transformation needs a hash argument" ) unless mapping.is_a?(Hash)
      new_headers = []
      headers.each do |key|
        new_headers << (mapping[key] ? mapping[key] : key)
      end
      new_headers
    }
    @@key_mapping.call(array, mapping)
  end

end
