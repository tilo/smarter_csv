module SmarterCSV
  # these are some pre-defined hash validations which can be used
  # all these take the hash as the input
  #
  # the computed options can be accessed via @options

  def self.required_fields(hash, required=[])
    @@required_fields ||= Proc.new {|hash, required=[]|
      raise( SmarterCSV::IncorrectOption , "ERROR: required_fields validation needs an array argument" ) unless required.is_a?(Array)
      count = 0
      required.each do |x|
        if ! hash.keys.include?(x) || hash[x].nil? || hash[x] =~ /\A\s+\z/ || hash[x] =~ /\A0\z/
          @errors[ @file_line_count ] ||= []
          @errors[ @file_line_count ] << "Missing required field `#{x.inspect}` in CSV line #{@file_line_count}"
          count += 1
        end
      end
      count
    }
    @@required_fields.call(hash,required)
  end
end
