# frozen_string_literal: true

module SmarterCSV
  # these are some pre-defined hash validations which can be used
  # all these take the hash as the input
  #
  # the computed options can be accessed via @options
  #
  # required_fields: [:first_name, :last_name, :age] # e.g. can't be blank or zero
  #
  def self.required_fields(hash, required=[])
    @@required_fields ||= proc {|hash, required=[]|
      raise(SmarterCSV::IncorrectOption , "ERROR: required_fields validation needs an array argument") unless required.is_a?(Array)
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
    @@required_fields.call(hash, required)
  end

  #
  # required_fields_matching: {
  #   first_name: /\A\w+\z/, last_name: /\A\w+\z/, employee_number: /\A[0-9]\d+\z/, email: /\A[^@]+@[^@]+\z/
  # }
  def self.required_fields_matching(hash, requirements_hash={})
    @@required_fields_matching ||= proc {|hash, requirements_hash={}|
      raise(SmarterCSV::IncorrectOption , "ERROR: required_fields_matching validation needs a hash argument") unless requirements_hash.is_a?(Hash)
      count = 0
      requirements_hash.each do |key, regex|
        if ! hash.keys.include?(key) || hash[key] !~ regex
          @errors[ @file_line_count ] ||= []
          @errors[ @file_line_count ] << "Field `#{key.inspect}` in CSV line #{@file_line_count}: `#{hash[key]}` did not match #{regex.inspect}"
          count += 1
        end
      end
      count
    }
    @@required_fields_matching.call(hash, requirements_hash)
  end
end
