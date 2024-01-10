# frozen_string_literal: true

module SmarterCSV
  COMMON_OPTIONS = {
    acceleration: true,
    auto_row_sep_chars: 500,
    chunk_size: nil,
    col_sep: :auto, # was: ',',
    comment_regexp: nil, # was: /\A#/,
    convert_values_to_numeric: true,
    downcase_header: true,
    duplicate_header_suffix: '', # was: nil,
    file_encoding: 'utf-8',
    force_simple_split: false,
    force_utf8: false,
    headers_in_file: true,
    invalid_byte_sequence: '',
    quote_char: '"',
    remove_unmapped_keys: false,
    row_sep: :auto, # was: $/,
    silence_deprecations: false, # new in 1.11
    silence_missing_keys: false,
    skip_lines: nil,
    user_provided_headers: nil,
    verbose: false,
    with_line_numbers: false,
    v2_mode: false,
  }.freeze

  V1_DEFAULT_OPTIONS = {
    keep_original_headers: false,
    key_mapping: nil,
    remove_empty_hashes: true,
    remove_empty_values: true,
    remove_values_matching: nil,
    remove_zero_values: false,
    required_headers: nil,
    required_keys: nil,
    strings_as_keys: false,
    strip_chars_from_headers: nil,
    strip_whitespace: true,
    value_converters: nil,
    v2_mode: false,
  }.freeze

  DEPRECATED_OPTIONS = [
    :convert_values_to_numeric,
    :downcase_headers,
    :keep_original_headers,
    :key_mapping,
    :remove_empty_hashes,
    :remove_empty_values,
    :remove_values_matching,
    :remove_zero_values,
    :required_headers,
    :required_keys,
    :stirngs_as_keys,
    :strip_cars_from_headers,
    :strip_whitespace,
    :value_converters,
  ].freeze

  class << self
    # NOTE: this is not called when "parse" methods are tested by themselves
    def process_options(given_options = {})
      puts "User provided options:\n#{pp(given_options)}\n" if given_options[:verbose]

      # fix invalid input
      given_options[:invalid_byte_sequence] = '' if given_options[:invalid_byte_sequence].nil?

      # warn about deprecated options / raises error for v2_mode
      handle_deprecations(given_options)

      given_options = preprocess_v2_options(given_options) if given_options[:v2_mode]

      @options = compute_default_options(given_options).merge!(given_options)
      puts "Computed options:\n#{pp(@options)}\n" if given_options[:verbose]

      validate_options!(@options)
      @options
    end

    # NOTE: this is not called when "parse" methods are tested by themselves
    #
    # ONLY FOR BACKWARDS-COMPATIBILITY
    def default_options
      COMMON_OPTIONS.merge(V1_DEFAULT_OPTIONS)
    end

    private

    def compute_default_options(options = {})
      return COMMON_OPTIONS.merge(V1_DEFAULT_OPTIONS) unless options[:v2_mode]

      default_options = {}
      if options[:defaults].to_s != 'none'
        default_options = COMMON_OPTIONS.dup.merge(V2_DEFAULT_OPTIONS)
        if options[:defaults].to_s == 'v1'
          default_options.merge(V1_TRANSFORMATIONS)
        else
          default_options.merge(V2_TRANSFORMATIONS)
        end
      end
    end

    def handle_deprecations(options)
      used_deprecated_options = DEPRECATED_OPTIONS & options.keys
      message = "SmarterCSV #{VERSION} DEPRECATED OPTIONS: #{pp(used_deprecated_options)}"
      if options[:v2_mode]
        raise(SmarterCSV::DeprecatedOptions, "ERROR: #{message}") unless used_deprecated_options.empty? || options[:silence_deprecations]
      else
        puts "DEPRECATION WARNING: #{message}" unless used_deprecated_options.empty? || options[:silence_deprecations]
      end
    end

    def validate_options!(options)
      # deprecate required_headers
      unless options[:required_headers].nil?
        puts "DEPRECATION WARNING: please use 'required_keys' instead of 'required_headers'"
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

    # ---- V2 code ----------------------------------------------------------------------------------------

    V2_DEFAULT_OPTIONS = {
      # These need to go to the COMMON_OPTIONS:
      remove_empty_hashes: true, # this might need a transformation or move to common options
      # ------------
      header_transformations: [:keys_as_symbols],
      header_validations: [:unique_headers],
      # data_transformations: [:replace_blank_with_nil],
      # data_validations: [],
      hash_transformations: [:strip_spaces, :remove_blank_values],
      hash_validations: [],
      v2_mode: true,
    }.freeze

    V2_TRANSFORMATIONS = {
      header_transformations: [:keys_as_symbols],
      header_validations: [:unique_headers],
      # data_transformations: [:replace_blank_with_nil],
      # data_validations: [],
      hash_transformations: [:v1_backwards_compatibility],
      # hash_transformations: [:remove_empty_keys, :strip_spaces, :remove_blank_values, :convert_values_to_numeric], # ??? :convert_values_to_numeric]
      hash_validations: [],
    }.freeze

    V1_TRANSFORMATIONS = {
      header_transformations: [:keys_as_symbols],
      header_validations: [:unique_headers],
      # data_transformations: [:replace_blank_with_nil],
      # data_validations: [],
      hash_transformations: [:strip_spaces, :remove_blank_values, :convert_values_to_numeric],
      hash_validations: [],
    }.freeze

    def preprocess_v2_options(options)
      return options unless options[:v2_mode] || options[:header_transformations]

      # We want to provide safe defaults for easy processing, that is why we have a special keyword :none
      # to not do any header transformations..
      #
      # this is why we need to remove the 'none' here:
      #
      requested_header_transformations = options[:header_transformations]
      if requested_header_transformations.to_s == 'none'
        requested_header_transformations = []
      else
        requested_header_transformations = requested_header_transformations.reject {|x| x.to_s == 'none'} unless requested_header_transformations.nil?
      end
      options[:header_transformations] = requested_header_transformations || []
      options
    end
  end
end
