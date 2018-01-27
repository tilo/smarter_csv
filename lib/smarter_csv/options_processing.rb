module SmarterCSV

# do we REALLY need a way to be v1.x backwards-compatible??

# TODO: we need to provide printing out all the currently used options in verbose mode, so people can check what their transformations/validations look like.

# Bye bye hash rocket! Ruby 1.9 introduced the new hash syntax. Ruby 1.8 was EOL 30 Jun 2013 .. no need to support it anymore


  # The default options for validations / transformations are needed for smooth operation of the gem.
  # User defined validations / transformations are added after these defaults.
  #
  # Data Transformation :replace_blank_with_nil is important, because there are no values set. (footnote 1)
  # Data Transformation :replace_blank_with_nil is important, because there are no values set. (footnote 1)
  # Hash transformation :strip_spaces is important because ' This', 'This ', and ' This ' should be 'This'.
  # Hash Transformation :remove_blank_values is important when you want to update database records. (footnote 1)
  #
  # Footnote 1:
  # If in a CSV file there is no value for a given column, this can be interpreted either as value currently not known,
  # or that the value is really an empty string.
  #
  # When you want to use CSV data to update database records, this difference becomes apparent:
  #   a) User.update_attributes(email: 'joe@test.com', department: 'Sales')
  #   b) User.update_attributes(email: 'joe@test.com', department: '')
  #   b) User.update_attributes(email: 'joe@test.com', department: nil)
  #
  # You could already have valid data in your DB for Joe, and the next CSV upload mistakenly does not list his department.
  # In that situation you don't want to zap valid data in the DB. Updating the department with '' or nil would overwrite valid data.
  #
  # SmarterCSV was designed to help load data from CSV into a DB, that's why :replace_blank_with_nil, :remove_blank_values
  # are considered "safe" defaults.
  #
  # If you don't like these defaults, you can override any or all of the validations/transformations by specifying :none
  # e.g.: `options = {hash_transformationss: :none, data_transformations: :none}` or `{defaults: :none}`

  # If you do not disable thedefault options as mentioned above,
  # and you define :header_transformations, :header_validations, :data_transformations, :hash_transformations,
  # those will be **appended** to the default values.
  #
  # e.g. you might want to add automatic conversions of numerical data from String to Fixnum or Float
  # using the pre-defined `:convert_values_to_numeric` or `:convert_values_to_numeric_unless_leading_zeroes`
  #
  #    `hash_transformations: [:convert_values_to_numeric_unless_leading_zeroes]
  #
  # This will then be applied **after** the defaults::strip_spaces, :remove_blank_values
  #
  # If you want to completely replace the default values, use `defaults: :none`, and you have full control.


  OBSOLETE_OPTIONS = [:remove_empty_values, :remove_zero_values, :remove_values_matching, :strip_whitespace,
    :convert_values_to_numeric, :strip_chars_from_headers, :key_mapping_hash, :downcase_header, :strings_as_keys,
    :remove_unmapped_keys, :keep_original_headers, :value_converters, :required_headers
  ]

  DEFAULT_OPTIONS = {
    file_encoding: 'utf-8', invalid_byte_sequence: '', force_utf8: false, skip_lines: nil, comment_regexp: /^#/,
    col_sep: ',', force_simple_split: false, row_sep: $/ , auto_row_sep_chars: 500,  quote_char: '"',
    chunk_size: nil, remove_empty_hashes: true, verbose: false,

    headers_in_file: true, user_provided_headers: nil,
  }

  BASE_TRANSFORMATIONS = {
    header_transformations: [:keys_as_symbols],
    header_validations:   [ :unique_headers ],
    data_transformations: [ :replace_blank_with_nil ],
    data_validations: [],
    hash_transformations: [ :strip_spaces, :remove_blank_values ],
  }

  V1_TRANSFORMATIONS = {
     header_transformations: [:keys_as_symbols],
     header_validations: [:unique_headers],
     data_transformations: [ :replace_blank_with_nil ],
    data_validations: [],
     hash_transformations: [:strip_spaces, :remove_blank_values, :convert_values_to_numeric]
  }

  def self.process_options(options={})

    puts "User provided options:\n#{pp(options)}\n" if options[:verbose]

    # warn about obsolete options
    used_obsolete_options = OBSOLETE_OPTIONS & options.keys
    raise( SmarterCSV::ObsoleteOptions, "ERROR: SmarterCSV #{VERSION} IGNORING OBSOLETE OPTIONS: #{pp(used_obsolete_options)}" ) unless used_obsolete_options.empty? || options[:silence_obsolete_error]

    default_options = {}
    if options[:defaults].to_s != 'none'
      default_options = DEFAULT_OPTIONS
      if options[:defaults].to_s == 'v1'
        default_options.merge!(V1_TRANSFORMATIONS)
      else
        default_options.merge!(BASE_TRANSFORMATIONS)
      end
    end

    requested_header_transformations = options.delete(:header_transformations)
    requested_header_validations = options.delete(:header_validations)
    requested_data_transformations = options.delete(:data_transformations)
    requested_data_validations = options.delete(:data_validations)
    requested_hash_transformations = options.delete(:hash_transformations)

    # default transformations and validations can be disabled individually
    default_options[:header_transformations] = [] if ['none', nil].include?( requested_header_transformations.to_s) || requested_header_transformations&.first.to_s == 'none'
    default_options[:header_validations] = []     if ['none', nil].include?( requested_header_validations.to_s) || requested_header_validations&.first.to_s == 'none'
    default_options[:data_transformations] = []   if ['none', nil].include?( requested_data_transformations.to_s) || requested_data_transformations&.first.to_s == 'none'
    default_options[:data_validations] = []   if ['none', nil].include?( requested_data_validations.to_s) || requested_data_validations&.first.to_s == 'none'
    default_options[:hash_transformations] = []   if ['none', nil].include?( requested_hash_transformations.to_s) || requested_hash_transformations&.first.to_s == 'none'

    if ['no_procs', 'none'].include?( options[:defaults].to_s) # you can disable all default transformations / validations
      default_options[:header_transformations] = []
      default_options[:header_validations] = []
      default_options[:data_transformations] = []
      default_options[:data_validations] = []
      default_options[:hash_transformations] = []
    end

    # remove the 'none'
    if requested_header_transformations.to_s == 'none'
      requested_header_transformations = []
    else
      requested_header_transformations&.reject!{|x| x.to_s == 'none'}
    end
    if requested_header_validations.to_s == 'none'
      requested_header_validations = []
    else
      requested_header_validations&.reject!{|x| x.to_s == 'none'}
    end
    if requested_data_transformations.to_s == 'none'
      requested_data_transformations = []
    else
      requested_data_transformations&.reject!{|x| x.to_s == 'none'}
    end
    if requested_data_validations.to_s == 'none'
      requested_data_validations = []
    else
      requested_data_validations&.reject!{|x| x.to_s == 'none'}
    end
    if requested_hash_transformations.to_s == 'none'
      requested_hash_transformations = []
    else
      requested_hash_transformations&.reject!{|x| x.to_s == 'none'}
    end

    # now append the user-defined validations / transformations:
    default_options[:header_transformations] += (requested_header_transformations || [])
    default_options[:header_validations]     += (requested_header_validations || [])
    default_options[:data_transformations]   += (requested_data_transformations || [])
    default_options[:data_validations]      += (requested_data_validations || [])
    default_options[:hash_transformations]   += (requested_hash_transformations || [])

    # use the default options unless user wants a clean slate
    options = default_options.merge(options) unless options[:defaults].to_s == 'none'

    # fix invalid input
    options[:invalid_byte_sequence] = '' if options[:invalid_byte_sequence].nil?

    puts "Computed options:\n#{pp(options)}\n" if options[:verbose]

    return options
  end

  private

  def pp(value)
    defined?(AwesomePrint) ? value.awesome_inspect(index: nil) : value.inspect
  end
end
