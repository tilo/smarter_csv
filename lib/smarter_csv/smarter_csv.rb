require_relative '../../ext/smarter_csv/smarter_csv'

module SmarterCSV
  class SmarterCSVException < StandardError; end
  class HeaderSizeMismatch < SmarterCSVException; end
  class IncorrectOption < SmarterCSVException; end
  class DuplicateHeaders < SmarterCSVException; end
  class MissingHeaders < SmarterCSVException; end
  class NoColSepDetected < SmarterCSVException; end
  class KeyMappingError < SmarterCSVException; end
  class MalformedCSVError < SmarterCSVException; end

  # first parameter: filename or input object which responds to readline method
  def SmarterCSV.process(input, options={}, &block)
    options = default_options.merge(options)
    options[:invalid_byte_sequence] = '' if options[:invalid_byte_sequence].nil?
    puts "SmarterCSV OPTIONS: #{options.inspect}" if options[:verbose]

    headerA = []
    result = []
    @file_line_count = 0
    @csv_line_count = 0
    has_rails = !! defined?(Rails)
    begin
      fh = input.respond_to?(:readline) ? input : File.open(input, "r:#{options[:file_encoding]}")

      # auto-detect the row separator
      options[:row_sep] = SmarterCSV.guess_line_ending(fh, options) if options[:row_sep].to_sym == :auto
      # attempt to auto-detect column separator
      options[:col_sep] = guess_column_separator(fh, options) if options[:col_sep].to_sym == :auto

      if (options[:force_utf8] || options[:file_encoding] =~ /utf-8/i) && ( fh.respond_to?(:external_encoding) && fh.external_encoding != Encoding.find('UTF-8') || fh.respond_to?(:encoding) && fh.encoding != Encoding.find('UTF-8') )
        puts 'WARNING: you are trying to process UTF-8 input, but did not open the input with "b:utf-8" option. See README file "NOTES about File Encodings".'
      end

      if options[:skip_lines].to_i > 0
        options[:skip_lines].to_i.times do
          readline_with_counts(fh, options)
        end
      end

      headerA, header_size = process_headers(fh, options)

      # in case we use chunking.. we'll need to set it up..
      if ! options[:chunk_size].nil? && options[:chunk_size].to_i > 0
        use_chunks = true
        chunk_size = options[:chunk_size].to_i
        chunk_count = 0
        chunk = []
      else
        use_chunks = false
      end

      # now on to processing all the rest of the lines in the CSV file:
      while ! fh.eof?    # we can't use fh.readlines() here, because this would read the whole file into memory at once, and eof => true
        line = readline_with_counts(fh, options)

        # replace invalid byte sequence in UTF-8 with question mark to avoid errors
        line = line.force_encoding('utf-8').encode('utf-8', invalid: :replace, undef: :replace, replace: options[:invalid_byte_sequence]) if options[:force_utf8] || options[:file_encoding] !~ /utf-8/i

        print "processing file line %10d, csv line %10d\r" % [@file_line_count, @csv_line_count] if options[:verbose]

        next if options[:comment_regexp] && line =~ options[:comment_regexp] # ignore all comment lines if there are any

        # cater for the quoted csv data containing the row separator carriage return character
        # in which case the row data will be split across multiple lines (see the sample content in spec/fixtures/carriage_returns_rn.csv)
        # by detecting the existence of an uneven number of quote characters

        multiline = line.count(options[:quote_char])%2 == 1 # should handle quote_char nil
        while line.count(options[:quote_char])%2 == 1 # should handle quote_char nil
          next_line = fh.readline(options[:row_sep])
          next_line = next_line.force_encoding('utf-8').encode('utf-8', invalid: :replace, undef: :replace, replace: options[:invalid_byte_sequence]) if options[:force_utf8] || options[:file_encoding] !~ /utf-8/i
          line += next_line
          @file_line_count += 1
        end
        print "\nline contains uneven number of quote chars so including content through file line %d\n" % @file_line_count if options[:verbose] && multiline

        line.chomp!(options[:row_sep])

        dataA, data_size = parse(line, options, header_size)

        dataA.map!{|x| x.strip} if options[:strip_whitespace]

        # if all values are blank, then ignore this line
        next if options[:remove_empty_hashes] && (dataA.empty? || blank?(dataA))

        hash = Hash.zip(headerA,dataA)  # from Facets of Ruby library

        # make sure we delete any key/value pairs from the hash, which the user wanted to delete:
        # Note: Ruby < 1.9 doesn't allow empty symbol literals!
        hash.delete(nil); hash.delete('');
        if RUBY_VERSION.to_f > 1.8
          eval('hash.delete(:"")')
        end

        if options[:remove_empty_values] == true
          return hash.delete_if{|k,v| v.blank?} if has_rails

          hash.delete_if{|k,v| blank?(v)}
        end

        hash.delete_if{|k,v| ! v.nil? && v =~ /^(\d+|\d+\.\d+)$/ && v.to_f == 0} if options[:remove_zero_values]   # values are typically Strings!
        hash.delete_if{|k,v| v =~ options[:remove_values_matching]} if options[:remove_values_matching]

        if options[:convert_values_to_numeric]
          hash.each do |k,v|
            # deal with the :only / :except options to :convert_values_to_numeric
            next if SmarterCSV.only_or_except_limit_execution( options, :convert_values_to_numeric , k )

            # convert if it's a numeric value:
            case v
            when /^[+-]?\d+\.\d+$/
              hash[k] = v.to_f
            when /^[+-]?\d+$/
              hash[k] = v.to_i
            end
          end
        end

        if options[:value_converters]
          hash.each do |k,v|
            converter = options[:value_converters][k]
            next unless converter
            hash[k] = converter.convert(v)
          end
        end

        next if hash.empty? if options[:remove_empty_hashes]

        if use_chunks
          chunk << hash  # append temp result to chunk

          if chunk.size >= chunk_size || fh.eof?   # if chunk if full, or EOF reached
            # do something with the chunk
            if block_given?
              yield chunk  # do something with the hashes in the chunk in the block
            else
              result << chunk  # not sure yet, why anybody would want to do this without a block
            end
            chunk_count += 1
            chunk = []  # initialize for next chunk of data
          else

            # the last chunk may contain partial data, which also needs to be returned (BUG / ISSUE-18)

          end

          # while a chunk is being filled up we don't need to do anything else here

        else # no chunk handling
          if block_given?
            yield [hash]  # do something with the hash in the block (better to use chunking here)
          else
            result << hash
          end
        end
      end

      # print new line to retain last processing line message
      print "\n" if options[:verbose]

      # last chunk:
      if ! chunk.nil? && chunk.size > 0
        # do something with the chunk
        if block_given?
          yield chunk  # do something with the hashes in the chunk in the block
        else
          result << chunk  # not sure yet, why anybody would want to do this without a block
        end
        chunk_count += 1
        chunk = []  # initialize for next chunk of data
      end
    ensure
      fh.close if fh.respond_to?(:close)
    end
    if block_given?
      return chunk_count  # when we do processing through a block we only care how many chunks we processed
    else
      return result # returns either an Array of Hashes, or an Array of Arrays of Hashes (if in chunked mode)
    end
  end

  private

  # NOTE: this is not called when "parse" methods are tested by themselves
  def self.default_options
    {
      acceleration: true,
      auto_row_sep_chars: 500,
      chunk_size: nil ,
      col_sep: ',',
      comment_regexp: nil, # was: /\A#/,
      convert_values_to_numeric: true,
      downcase_header: true,
      duplicate_header_suffix: nil,
      file_encoding: 'utf-8',
      force_simple_split: false ,
      force_utf8: false,
      headers_in_file: true,
      invalid_byte_sequence: '',
      keep_original_headers: false,
      key_mapping_hash: nil ,
      quote_char: '"',
      remove_empty_hashes: true ,
      remove_empty_values: true,
      remove_unmapped_keys: false,
      remove_values_matching: nil,
      remove_zero_values: false,
      required_headers: nil,
      row_sep: $INPUT_RECORD_SEPARATOR,
      skip_lines: nil,
      strings_as_keys: false,
      strip_chars_from_headers: nil,
      strip_whitespace: true,
      user_provided_headers: nil,
      value_converters: nil,
      verbose: false,
    }
  end

  def self.readline_with_counts(filehandle, options)
    line  = filehandle.readline(options[:row_sep])
    @file_line_count += 1
    @csv_line_count += 1
    line
  end

  ###
  ### Thin wrapper around C-extension
  ###
  def self.parse(line, options, header_size = nil)
    # puts "SmarterCSV.parse OPTIONS: #{options[:acceleration]}" if options[:verbose]

    if options[:acceleration] && defined?(parse_csv_line_c)
      # puts "NOTICE: Accelerated SmarterCSV / #{options[:acceleration]}" if options[:verbose]
      has_quotes = line =~ /#{options[:quote_char]}/
      elements = parse_csv_line_c(line, options[:col_sep], options[:quote_char], header_size)
      elements.map!{|x| cleanup_quotes(x, options[:quote_char])} if has_quotes
      return [elements, elements.size]
    else
      # puts "WARNING: SmarterCSV is using un-accelerated parsing of lines. Check options[:acceleration]"
      return parse_csv_line_ruby(line, options, header_size)
    end
  end

  # ------------------------------------------------------------------
  # Ruby equivalent of the C-extension for parse_line
  #
  # parses a single line: either a CSV header and body line
  # - quoting rules compared to RFC-4180 are somewhat relaxed
  # - we are not assuming that quotes inside a fields need to be doubled
  # - we are not assuming that all fields need to be quoted (0 is even)
  # - works with multi-char col_sep
  # - if header_size is given, only up to header_size fields are parsed
  #
  # We use header_size for parsing the body lines to make sure we always match the number of headers
  # in case there are trailing col_sep characters in line
  #
  # Our convention is that empty fields are returned as empty strings, not as nil.
  #
  #
  # the purpose of the max_size parameter is to handle a corner case where
  # CSV lines contain more fields than the header.
  # In which case the remaining fields in the line are ignored
  #
  def self.parse_csv_line_ruby(line, options, header_size = nil)
    return [] if line.nil?

    line_size = line.size
    col_sep = options[:col_sep]
    col_sep_size = col_sep.size
    quote = options[:quote_char]
    quote_count = 0
    elements = []
    start = 0
    i = 0

    while i < line_size do
      if line[i...i+col_sep_size] == col_sep && quote_count.even?
        break if !header_size.nil? && elements.size >= header_size

        elements << cleanup_quotes(line[start...i], quote)
        i += col_sep.size
        start = i
      else
        quote_count += 1 if line[i] == quote
        i += 1
      end
    end
    elements << cleanup_quotes(line[start..-1], quote) if header_size.nil? || elements.size < header_size
    [elements, elements.size]
  end

  def self.cleanup_quotes(field, quote)
    return field if field.nil?
    # return if field !~ /#{quote}/ # this check can probably eliminated

    if field.start_with?(quote) && field.end_with?(quote)
      field.delete_prefix!(quote)
      field.delete_suffix!(quote)
    end
    field.gsub!("#{quote}#{quote}", quote)
    field
  end

  # SEE: https://github.com/rails/rails/blob/32015b6f369adc839c4f0955f2d9dce50c0b6123/activesupport/lib/active_support/core_ext/object/blank.rb#L121
  # and in the future we might also include UTF-8 space characters: https://www.compart.com/en/unicode/category/Zs
  BLANK_RE = /\A\s*\z/

  def self.blank?(value)
    case value
    when String
      value.empty? || BLANK_RE.match?(value)

    when NilClass
      true

    when Array
      value.empty? || value.inject(true){|result, x| result &&= elem_blank?(x)}

    when Hash
      value.empty? || value.values.inject(true){|result, x| result &&= elem_blank?(x)}

    else
      false
    end
  end

  def self.elem_blank?(value)
    case value
    when String
      value.empty? || BLANK_RE.match?(value)

    when NilClass
      true

    else
      false
    end
  end

  # acts as a road-block to limit processing when iterating over all k/v pairs of a CSV-hash:
  def self.only_or_except_limit_execution( options, option_name, key )
    if options[option_name].is_a?(Hash)
      if options[option_name].has_key?( :except )
        return true if Array( options[ option_name ][:except] ).include?(key)
      elsif options[ option_name ].has_key?(:only)
        return true unless Array( options[ option_name ][:only] ).include?(key)
      end
    end
    return false
  end

  # raise exception if none is found
  def self.guess_column_separator(filehandle, options)
    del = [',', "\t", ';', ':', '|']
    n = Hash.new(0)
    5.times do
      line = filehandle.readline(options[:row_sep])
      del.each do |d|
        n[d] += line.scan(d).count
      end
    rescue EOFError # short files
      break
    end
    filehandle.rewind
    raise SmarterCSV::NoColSepDetected if n.values.max == 0

    col_sep = n.key(n.values.max)
  end

  # limitation: this currently reads the whole file in before making a decision
  def self.guess_line_ending( filehandle, options )
    counts = {"\n" => 0 , "\r" => 0, "\r\n" => 0}
    quoted_char = false

    # count how many of the pre-defined line-endings we find
    # ignoring those contained within quote characters
    last_char = nil
    lines = 0
    filehandle.each_char do |c|
      quoted_char = !quoted_char if c == options[:quote_char]
      next if quoted_char

      if last_char == "\r"
        if c == "\n"
          counts["\r\n"] +=  1
        else
          counts["\r"] += 1  # \r are counted after they appeared
        end
      elsif c == "\n"
        counts["\n"] += 1
      end
      last_char = c
      lines += 1
      break if options[:auto_row_sep_chars] && options[:auto_row_sep_chars] > 0 && lines >= options[:auto_row_sep_chars]
    end
    filehandle.rewind

    counts["\r"] += 1 if last_char == "\r"
    # find the key/value pair with the largest counter:
    k,_ = counts.max_by{|_,v| v}
    return k                    # the most frequent one is it
  end

  def self.raw_header
    @raw_header
  end

  def self.headers
    @headers
  end

  def self.process_headers(filehandle, options)
    @raw_header = nil
    @headers = nil
    if options[:headers_in_file]        # extract the header line
      # process the header line in the CSV file..
      # the first line of a CSV file contains the header .. it might be commented out, so we need to read it anyhow
      header = readline_with_counts(filehandle, options)
      @raw_header = header

      header = header.force_encoding('utf-8').encode('utf-8', invalid: :replace, undef: :replace, replace: options[:invalid_byte_sequence]) if options[:force_utf8] || options[:file_encoding] !~ /utf-8/i
      header = header.sub(options[:comment_regexp],'') if options[:comment_regexp]
      header = header.chomp(options[:row_sep])

      header = header.gsub(options[:strip_chars_from_headers], '') if options[:strip_chars_from_headers]

      file_headerA, file_header_size = parse(header, options)

      file_headerA.map!{|x| x.gsub(%r/#{options[:quote_char]}/,'') }
      file_headerA.map!{|x| x.strip}  if options[:strip_whitespace]
      unless options[:keep_original_headers]
        file_headerA.map!{|x| x.gsub(/\s+|-+/,'_')}
        file_headerA.map!{|x| x.downcase }   if options[:downcase_header]
      end
    else
      raise SmarterCSV::IncorrectOption , "ERROR: If :headers_in_file is set to false, you have to provide :user_provided_headers" unless options[:user_provided_headers]
    end
    if options[:user_provided_headers] && options[:user_provided_headers].class == Array && ! options[:user_provided_headers].empty?
      # use user-provided headers
      headerA = options[:user_provided_headers]
      if defined?(file_header_size) && ! file_header_size.nil?
        if headerA.size != file_header_size
          raise SmarterCSV::HeaderSizeMismatch , "ERROR: :user_provided_headers defines #{headerA.size} headers !=  CSV-file has #{file_header_size} headers"
        else
          # we could print out the mapping of file_headerA to headerA here
        end
      end
    else
      headerA = file_headerA
    end

    # detect duplicate headers and disambiguate
    headerA = process_duplicate_headers(headerA, options) if options[:duplicate_header_suffix]
    header_size = headerA.size # used for splitting lines

    headerA.map!{|x| x.to_sym } unless options[:strings_as_keys] || options[:keep_original_headers]

    unless options[:user_provided_headers] # wouldn't make sense to re-map user provided headers
      key_mappingH = options[:key_mapping]

      # do some key mapping on the keys in the file header
      #   if you want to completely delete a key, then map it to nil or to ''
      if ! key_mappingH.nil? && key_mappingH.class == Hash && key_mappingH.keys.size > 0
        # we can't map keys that are not there
        missing_keys = key_mappingH.keys - headerA
        puts "WARNING: missing header(s): #{missing_keys.join(",")}" unless missing_keys.empty?

        headerA.map!{|x| key_mappingH.has_key?(x) ? (key_mappingH[x].nil? ? nil : key_mappingH[x]) : (options[:remove_unmapped_keys] ? nil : x)}
      end
    end

    # header_validations
    duplicate_headers = []
    headerA.compact.each do |k|
      duplicate_headers << k if headerA.select{|x| x == k}.size > 1
    end

    unless duplicate_headers.empty? || options[:user_provided_headers]
      raise SmarterCSV::DuplicateHeaders , "ERROR: duplicate headers: #{duplicate_headers.join(',')}"
    end

    if options[:required_headers] && options[:required_headers].is_a?(Array)
      missing_headers = []
      options[:required_headers].each do |k|
        missing_headers << k unless headerA.include?(k)
      end
      raise SmarterCSV::MissingHeaders , "ERROR: missing headers: #{missing_headers.join(',')}" unless missing_headers.empty?
    end

    @headers = headerA
    [headerA, header_size]
  end

  def self.process_duplicate_headers(headers, options)
    counts = Hash.new(0)
    result = []
    headers.each do |key|
      counts[key] += 1
      if counts[key] == 1
        result << key
      else
        result << [key, options[:duplicate_header_suffix], counts[key]].join
      end
    end
    result
  end
end
