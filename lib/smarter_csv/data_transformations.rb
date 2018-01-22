module SmarterCSV
  # these are some pre-defined data transformations which can be used
  # all these take the data array as the input

  def self.replace_blank_with_nil(array)
    @@replace_blank_with_nil ||= Proc.new {|array|
      array.map{|x| x.is_a?(String) && x !~ /[^[:space:]]/ ? nil : x }
    }
    @@replace_blank_with_nil.call(array)
  end
end
