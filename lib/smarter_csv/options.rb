# frozen_string_literal: true

module SmarterCSV
  #
  # NOTE: this is not called when "parse" methods are tested by themselves
  #
  # ONLY FOR BACKWARDS-COMPATIBILITY
  def self.default_options
    Options::DEFAULT_OPTIONS
  end

  module Options
    DEFAULT_OPTIONS = {
      acceleration: true, # if user wants to use accelleration or not
      auto_row_sep_chars: 500,
      bad_row_limit: nil,
      chunk_size: nil,
      col_sep: :auto, # was: ',',
      collect_raw_lines: true,
      comment_regexp: nil, # was: /\A#/,
      convert_values_to_numeric: true,
      downcase_header: true,
      duplicate_header_suffix: '', # was: nil,
      field_size_limit: nil, # Integer (bytes) or nil for no limit. Raises FieldSizeLimitExceeded if any
      #                          extracted field exceeds this size. Prevents DoS from runaway quoted
      #                          fields (unbounded multiline stitching) or huge inline payloads.
      file_encoding: 'utf-8',
      force_utf8: false,
      headers_in_file: true,
      invalid_byte_sequence: '',
      keep_original_headers: false,
      key_mapping: nil,
      strict: false,              # DEPRECATED -> use missing_headers
      missing_headers: :auto,     # :auto (auto-generate names for extra cols) or :raise (raise HeaderSizeMismatch)
      missing_header_prefix: 'column_',
      nil_values_matching: nil,   # regex: set matching values to nil (key kept); pairs with remove_empty_values
      on_bad_row: :raise,
      on_chunk: nil,    # callable: fired after each chunk is parsed, before yielding to the block
      on_complete: nil, # callable: fired once after the entire file is processed
      on_start: nil,    # callable: fired once before the first row is parsed
      quote_boundary: :standard, # :standard (only at field boundary 👍) or :legacy (any quote toggles state 👎)
      quote_char: '"',
      quote_escaping: :auto,
      remove_empty_hashes: true,
      remove_empty_values: true,
      remove_unmapped_keys: false,
      remove_values_matching: nil, # DEPRECATED: use nil_values_matching instead
      remove_zero_values: false,
      required_headers: nil,
      required_keys: nil,
      row_sep: :auto, # was: $/,
      silence_missing_keys: false,
      skip_lines: nil,
      strings_as_keys: false,
      strip_chars_from_headers: nil,
      strip_whitespace: true,
      user_provided_headers: nil,
      value_converters: nil,
      verbose: :normal, # nil/:normal (default), :quiet (suppress warnings), :debug (print diagnostics); true/false are deprecated
      with_line_numbers: false,
    }.freeze

    # NOTE: this is not called when "parse" methods are tested by themselves
    def process_options(given_options = {})
      # Debug output before merge — check raw verbose value (true or :debug)
      $stderr.puts "User provided options:\n#{pp(given_options)}\n" if [true, :debug].include?(given_options[:verbose])

      # Special case for :user_provided_headers:
      #
      # If we would use the default `headers_in_file: true`, and `:user_provided_headers` are given,
      # we could lose the first data row
      #
      # We now err on the side of treating an actual header as data, rather than losing a data row.
      #
      if given_options[:user_provided_headers] && !given_options.keys.include?(:headers_in_file)
        given_options[:headers_in_file] = false
        warn "WARNING: setting `headers_in_file: false` as a precaution to not lose the first row. Set explicitly to `true` if you have headers." unless given_options[:verbose] == :quiet
      end

      @options = DEFAULT_OPTIONS.dup.merge!(given_options)

      # Normalize verbose to a symbol — done once here, stored back into @options.
      # All subsequent checks are free symbol comparisons; no re-evaluation needed.
      #   :quiet  — suppress all warnings and notices (good for production)
      #   :normal — show behavioral warnings (default; helpful for new users)
      #   :debug  — :normal + print computed options and per-row diagnostics
      # nil is silently normalized to :normal; true/false are deprecated.
      case @options[:verbose]
      when :quiet, :normal, :debug
        # keep as is
      when nil
        @options[:verbose] = :normal
      when false
        warn "DEPRECATION WARNING: verbose: false is deprecated. Use verbose: :normal instead (or omit — it is the default)."
        @options[:verbose] = :normal
      when true
        warn "DEPRECATION WARNING: verbose: true is deprecated. Use verbose: :debug instead."
        @options[:verbose] = :debug
      else
        warn "WARNING: unknown verbose value #{@options[:verbose].inspect}, defaulting to :normal. Valid values: :quiet, :normal, :debug."
        @options[:verbose] = :normal
      end

      # fix invalid input
      @options[:invalid_byte_sequence] ||= ''

      # Normalize headers: { only: [...] } / { except: [...] } to internal option names.
      # The public API is headers: { only: } or headers: { except: }.
      # Internally we use only_headers: / except_headers: (what the C extension reads).
      if (hdr = @options.delete(:headers)).is_a?(Hash)
        @options[:only_headers]   = hdr[:only]   if hdr.key?(:only)
        @options[:except_headers] = hdr[:except] if hdr.key?(:except)
      end

      # Deprecation: direct use of only_headers: / except_headers: (use headers: { only: } instead)
      if given_options.key?(:only_headers) && !given_options.key?(:headers)
        warn "DEPRECATION WARNING: 'only_headers:' is deprecated. Use 'headers: { only: [...] }' instead." unless @options[:verbose] == :quiet
      end
      if given_options.key?(:except_headers) && !given_options.key?(:headers)
        warn "DEPRECATION WARNING: 'except_headers:' is deprecated. Use 'headers: { except: [...] }' instead." unless @options[:verbose] == :quiet
      end

      # Normalize only_headers/except_headers to arrays of symbols (internal names, read by C extension)
      if @options[:only_headers]
        values = Array(@options[:only_headers])
        bad = values.reject { |v| v.is_a?(Symbol) || v.is_a?(String) }
        raise SmarterCSV::ValidationError, "headers: { only: } elements must be String or Symbol, got: #{bad.map(&:class).uniq.inspect}" if bad.any?
        @options[:only_headers] = values.map(&:to_sym)
      end
      if @options[:except_headers]
        values = Array(@options[:except_headers])
        bad = values.reject { |v| v.is_a?(Symbol) || v.is_a?(String) }
        raise SmarterCSV::ValidationError, "headers: { except: } elements must be String or Symbol, got: #{bad.map(&:class).uniq.inspect}" if bad.any?
        @options[:except_headers] = values.map(&:to_sym)
      end

      # Deprecation: remove_values_matching → nil_values_matching
      # Old behavior: removes the key-value pair entirely.
      # New behavior: nil_values_matching sets the value to nil (key kept);
      # combined with the default remove_empty_values: true the net effect is identical.
      # With remove_empty_values: false, the key is retained with a nil value.
      if given_options.key?(:remove_values_matching)
        unless @options[:verbose] == :quiet
          warn "DEPRECATION WARNING: 'remove_values_matching' is deprecated. " \
               "Use 'nil_values_matching' instead. With the default 'remove_empty_values: true' " \
               "the net behavior is identical. With 'remove_empty_values: false', matching values " \
               "are set to nil but the key is retained in the result hash."
        end
        @options[:nil_values_matching] ||= @options[:remove_values_matching]
        @options[:remove_values_matching] = nil # clear to prevent double-processing
      end

      # Translate deprecated :strict option to :missing_headers
      if given_options.key?(:strict)
        unless @options[:verbose] == :quiet
          warn "DEPRECATION WARNING: 'strict' option is deprecated and will be removed in a future version. " \
               "Use 'missing_headers: :raise' instead of 'strict: true', or 'missing_headers: :auto' instead of 'strict: false'."
        end
        @options[:missing_headers] = @options[:strict] ? :raise : :auto unless given_options.key?(:missing_headers)
      end

      # Keep :strict synchronized with :missing_headers (C extension reads :strict directly)
      @options[:strict] = (@options[:missing_headers] == :raise)

      $stderr.puts "Computed options:\n#{pp(@options)}\n" if @options[:verbose] == :debug

      validate_options!(@options)
      @options
    end

    private

    def validate_options!(options)
      # deprecate required_headers
      unless options[:required_headers].nil?
        warn "DEPRECATION WARNING: please use 'required_keys' instead of 'required_headers'" unless options[:verbose] == :quiet
        if options[:required_keys].nil?
          options[:required_keys] = options[:required_headers]
          options[:required_headers] = nil
        end
      end

      keys = options.keys
      errors = []
      errors << "invalid row_sep" if keys.include?(:row_sep) && !option_valid?(options[:row_sep])
      errors << "invalid col_sep" if keys.include?(:col_sep) && !option_valid?(options[:col_sep])
      errors << "invalid quote_char" if keys.include?(:quote_char) && !option_valid?(options[:quote_char])
      if keys.include?(:quote_char) && options[:quote_char].is_a?(String) && options[:quote_char].bytesize > 1
        errors << "invalid quote_char: must be a single byte (got #{options[:quote_char].inspect})"
      end
      unless %i[double_quotes backslash auto].include?(options[:quote_escaping])
        errors << "invalid quote_escaping: must be :double_quotes, :backslash, or :auto"
      end
      unless %i[legacy standard].include?(options[:quote_boundary])
        errors << "invalid quote_boundary: must be :legacy or :standard"
      end
      fsl = options[:field_size_limit]
      unless fsl.nil? || (fsl.is_a?(Integer) && fsl > 0)
        errors << "invalid field_size_limit: must be nil or a positive Integer (got #{fsl.inspect})"
      end
      obr = options[:on_bad_row]
      unless %i[raise skip collect].include?(obr) || obr.respond_to?(:call)
        errors << "invalid on_bad_row: must be :raise, :skip, :collect, or a callable"
      end
      %i[on_start on_chunk on_complete].each do |hook|
        val = options[hook]
        errors << "invalid #{hook}: must be nil or a callable" if !val.nil? && !val.respond_to?(:call)
      end
      unless %i[auto raise].include?(options[:missing_headers])
        errors << "invalid missing_headers: must be :auto or :raise"
      end
      if options[:only_headers] && options[:except_headers]
        errors << "cannot use both 'headers: { only: }' and 'headers: { except: }' at the same time"
      end
      raise SmarterCSV::ValidationError, errors.inspect if errors.any?
    end

    def option_valid?(str)
      return true if str.is_a?(Symbol) && str == :auto
      return true if str.is_a?(String) && !str.empty?

      false
    end

    def pp(value)
      defined?(AwesomePrint) ? value.awesome_inspect(index: nil) : value.inspect
    end
  end
end
