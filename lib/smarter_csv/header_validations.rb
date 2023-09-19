# frozen_string_literal: true

module SmarterCSV
  # these are some pre-defined header validations which can be used
  # all these take the headers array as the input
  #
  # the computed options can be accessed via @options

  @unique_headers = nil

  def self.unique_headers(array)
    @unique_headers ||= proc {|headers|
      dupes = headers.each_with_object({}) do |x, h|
        # when we remove fields we map them to nil - we don't count these as dupes
        h[x] ||= 0
        h[x] += 1
      end.reject do |k, v|
        k.nil? || v < 2
      end
      dupes.empty? ? nil : raise(SmarterCSV::DuplicateHeaders, "Duplicate Headers in CSV: #{dupes.inspect}")
    }
    @unique_headers.call(array)
  end

  @required_headers = nil

  def self.required_headers(array, required = [])
    @required_headers ||= proc {|headers, required = []|
      raise(SmarterCSV::IncorrectOption, "ERROR: required_headers validation needs an array argument") unless required.is_a?(Array)

      missing = required.each_with_object([]){ |x, a| a << x unless headers.include?(x) }
      missing.empty? ? nil : raise(SmarterCSV::MissingHeaders, "Missing Headers in CSV: #{missing.inspect}")
    }
    @required_headers.call(array, required)
  end
end
