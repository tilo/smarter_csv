# frozen_string_literal: true

module SmarterCSV
  class << self
    attr_reader :csv_line_count, :chunk_count, :errors, :file_line_count, :headers, :raw_header, :result, :warnings

    def initialize_variables
      @csv_line_count = 0
      @chunk_count = 0
      @errors = {}
      @file_line_count = 0
      @headerA = []
      @headers = nil
      @raw_header = nil # header as it appears in the file
      @result = []
      @warnings = {}
    end

    def headerA
      warn "Deprecarion Warning: 'headerA' will be removed in future versions. Use 'headders'"
      @headerA
    end
  end
end
