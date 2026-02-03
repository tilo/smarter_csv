# frozen_string_literal: true

module SmarterCSV
  class Error < StandardError; end # new code should rescue this instead
  # Reader:
  class SmarterCSVException < Error; end # for backwards compatibility
  class HeaderSizeMismatch < SmarterCSVException; end
  class IncorrectOption < SmarterCSVException; end
  class ValidationError < SmarterCSVException; end
  class DuplicateHeaders < SmarterCSVException
    attr_reader :headers

    def initialize(message, headers = [])
      super(message)
      @headers = headers
    end
  end

  class MissingKeys < SmarterCSVException # previously known as MissingHeaders
    attr_reader :keys

    def initialize(message, keys = [])
      super(message)
      @keys = keys
    end
  end

  class NoColSepDetected < SmarterCSVException; end
  class KeyMappingError < SmarterCSVException; end
  class MalformedCSV < SmarterCSVException; end
  # Writer:
  class InvalidInputData < SmarterCSVException; end
end
