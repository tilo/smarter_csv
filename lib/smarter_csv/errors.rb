# frozen_string_literal: true

module SmarterCSV
  class Error < StandardError; end # new code should rescue this instead
  # Reader:
  class SmarterCSVException < Error; end # for backwards compatibility
  class HeaderSizeMismatch < SmarterCSVException; end
  class IncorrectOption < SmarterCSVException; end
  class ValidationError < SmarterCSVException; end
  class DuplicateHeaders < SmarterCSVException; end
  class MissingKeys < SmarterCSVException; end # previously known as MissingHeaders
  class NoColSepDetected < SmarterCSVException; end
  class KeyMappingError < SmarterCSVException; end
  # Writer:
  class InvalidInputData < SmarterCSVException; end
end
