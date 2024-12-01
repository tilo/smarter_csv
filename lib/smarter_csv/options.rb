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
      chunk_size: nil,
      col_sep: :auto, # was: ',',
      comment_regexp: nil, # was: /\A#/,
      convert_values_to_numeric: true,
      downcase_header: true,
      duplicate_header_suffix: '', # was: nil,
      file_encoding: 'utf-8',
      force_utf8: false,
      headers_in_file: true,
      invalid_byte_sequence: '',
      keep_original_headers: false,
      key_mapping: nil,
      missing_header_prefix: 'column_',
      quote_char: '"',
      remove_empty_hashes: true,
      remove_empty_values: true,
      remove_unmapped_keys: false,
      remove_values_matching: nil,
      remove_zero_values: false,
      required_headers: nil,
      required_keys: nil,
      row_sep: :auto, # was: $/,
      silence_missing_keys: false,
      skip_lines: nil,
      strict: false,
      strings_as_keys: false,
      strip_chars_from_headers: nil,
      strip_whitespace: true,
      user_provided_headers: nil,
      value_converters: nil,
      verbose: false,
      with_line_numbers: false,
    }.freeze

    # NOTE: this is not called when "parse" methods are tested by themselves
    def process_options(given_options = {})
      puts "User provided options:\n#{pp(given_options)}\n" if given_options[:verbose]

      # Special case for :user_provided_headers:
      #
      # If we would use the default `headers_in_file: true`, and `:user_provided_headers` are given,
      # we could lose the first data row
      #
      # We now err on the side of treating an actual header as data, rather than losing a data row.
      #
      if given_options[:user_provided_headers] && !given_options.keys.include?(:headers_in_file)
        given_options[:headers_in_file] = false
        puts "WARNING: setting `headers_in_file: false` as a precaution to not lose the first row. Set explicitly to `true` if you have headers."
      end

      @options = DEFAULT_OPTIONS.dup.merge!(given_options)

      # fix invalid input
      @options[:invalid_byte_sequence] ||= ''

      puts "Computed options:\n#{pp(@options)}\n" if @options[:verbose]

      validate_options!(@options)
      @options
    end

    private

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
  end
end
