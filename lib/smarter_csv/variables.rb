# frozen_string_literal: true

require "forwardable"

module SmarterCSV
  Instance = Struct.new(
    :has_rails, :csv_line_count, :chunk_count, :errors, :file_line_count, :headers, :raw_header, :result, :warnings,
    :enforce_utf8, :verbose,
    :has_acceleration,
    :header_a, # deprecated
    keyword_init: true
  ) do
    # :nocov:
    # rubocop:disable Naming/MethodName
    def headerA
      warn "Deprecation Warning: 'headerA' will be removed in future versions. Use 'headers'"
      header_a
    end
    # rubocop:enable Naming/MethodName
    # :nocov:

    def has_acceleration?
      has_acceleration
    end
  end

  class << self
    extend Forwardable

    # Backwards compatibility
    # If anyone was using the instance variables directly on the SmarterCSV module before, they should still be
    #   able to while also maintaining them in a thread-safe way.
    def compatibility_instance
      Thread.current[:smarter_csv_compatibility_instance]
    end

    def compatibility_instance=(instance)
      Thread.current[:smarter_csv_compatibility_instance] = instance
    end

    def_delegators :compatibility_instance,
      :headers, :raw_header, :result, :errors, :warnings, :csv_line_count, :file_line_count, :chunk_count,
      :has_rails, :has_acceleration, :has_acceleration?, :enforce_utf8, :verbose

    def initialize_variables
      Instance.new(
        has_rails: !!defined?(Rails),
        csv_line_count: 0,
        chunk_count: 0,
        errors: {},
        file_line_count: 0,
        header_a: [], # only set to true if needed (after options parsing)
        headers: nil,
        raw_header: nil, # header as it appears in the file
        result: [],
        warnings: {},
        enforce_utf8: false,
        has_acceleration: !!defined?(parse_csv_line_c)
      )
    end
  end
end
