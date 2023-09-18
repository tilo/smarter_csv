# frozen_string_literal: true

module SmarterCSV
  # these are some pre-defined data transformations which can be used
  # all these take the data array as the input
  #
  # the computed options can be accessed via @options

  def self.replace_blank_with_nil(array)
    @@replace_blank_with_nil ||= proc {|array|
      array.map{|x| x.is_a?(String) && x !~ /[^[:space:]]/ ? nil : x }
    }
    @@replace_blank_with_nil.call(array)
  end

  def self.remove_quote_chars(array)
    @@remove_quote_chars ||= proc {|array|
      array.map{|x| x.is_a?(String) ? x.gsub(%r{#{@options[:quote_char]}}, '') : x }
    }
    @@remove_quote_chars.call(array)
  end
end
