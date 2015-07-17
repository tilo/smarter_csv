module SmarterCSV

  class HeaderSizeMismatch < Exception; end

  class IncorrectOption < Exception; end

  def SmarterCSV.process(input, options={}, &block)   # first parameter: filename or input object with readline method
    default_options = {:col_sep => ',' , :row_sep => $/ , :quote_char => '"', :force_simple_split => false , :verbose => false ,
      :remove_empty_values => true, :remove_zero_values => false , :remove_values_matching => nil , :remove_empty_hashes => true , :strip_whitespace => true,
      :convert_values_to_numeric => true, :strip_chars_from_headers => nil , :user_provided_headers => nil , :headers_in_file => true,
      :comment_regexp => /^#/, :chunk_size => nil , :key_mapping_hash => nil , :downcase_header => true, :strings_as_keys => false, :file_encoding => 'utf-8',
      :remove_unmapped_keys => false, :keep_original_headers => false, :invalid_byte_sequence => '?'
    }
    options = default_options.merge(options)
    csv_options = options.select{|k,v| [:col_sep, :row_sep, :quote_char].include?(k)} # options.slice(:col_sep, :row_sep, :quote_char)
    headerA = []
    result = []
    old_row_sep = $/
    line_count = 0
    begin
      f = input.respond_to?(:readline) ? input : File.open(input, "r:#{options[:file_encoding]}")

      if options[:row_sep] == :auto
        options[:row_sep] =  SmarterCSV.guess_line_ending( f, options )
        f.rewind
      end
      $/ = options[:row_sep]

      if options[:headers_in_file]        # extract the header line
        # process the header line in the CSV file..
        # the first line of a CSV file contains the header .. it might be commented out, so we need to read it anyhow
        header = f.readline.sub(options[:comment_regexp],'').chomp(options[:row_sep])
        line_count += 1
        header = header.gsub(options[:strip_chars_from_headers], '') if options[:strip_chars_from_headers]
        if (header =~ %r{#{options[:quote_char]}}) and (! options[:force_simple_split])
          file_headerA = CSV.parse( header, csv_options ).flatten.collect!{|x| x.nil? ? '' : x} # to deal with nil values from CSV.parse
        else
          file_headerA =  header.split(options[:col_sep])
        end
        file_headerA.map!{|x| x.gsub(%r/options[:quote_char]/,'') }
        file_headerA.map!{|x| x.strip}  if options[:strip_whitespace]
        unless options[:keep_original_headers]
          file_headerA.map!{|x| x.gsub(/\s+/,'_')}
          file_headerA.map!{|x| x.downcase }   if options[:downcase_header]
        end

#        puts "HeaderA: #{file_headerA.join(' , ')}" if options[:verbose]

        file_header_size = file_headerA.size
      end
      if options[:user_provided_headers] && options[:user_provided_headers].class == Array && ! options[:user_provided_headers].empty?
        # use user-provided headers
        headerA = options[:user_provided_headers]
        if defined?(file_header_size) && ! file_header_size.nil?
          if headerA.size != file_header_size
            raise SmarterCSV::HeaderSizeMismatch , "ERROR [smarter_csv]: :user_provided_headers defines #{headerA.size} headers !=  CSV-file #{input} has #{file_header_size} headers"
          else
            # we could print out the mapping of file_headerA to headerA here
          end
        end
      else
        headerA = file_headerA
      end
      headerA.map!{|x| x.to_sym } unless options[:strings_as_keys] || options[:keep_original_headers]

      unless options[:user_provided_headers] # wouldn't make sense to re-map user provided headers
        key_mappingH = options[:key_mapping]

        # do some key mapping on the keys in the file header
        #   if you want to completely delete a key, then map it to nil or to ''
        if ! key_mappingH.nil? && key_mappingH.class == Hash && key_mappingH.keys.size > 0
          headerA.map!{|x| key_mappingH.has_key?(x) ? (key_mappingH[x].nil? ? nil : key_mappingH[x].to_sym) : (options[:remove_unmapped_keys] ? nil : x)}
        end
      end

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
      while ! f.eof?    # we can't use f.readlines() here, because this would read the whole file into memory at once, and eof => true
        line = f.readline  # read one line.. this uses the input_record_separator $/ which we set previously!
        # replace invalid byte sequence in UTF-8 with question mark to avoid errors
        line = line.encode('UTF-8', 'binary', invalid: :replace, undef: :replace, replace: options[:invalid_byte_sequence]) if options[:file_encoding] == 'utf-8'
        line_count += 1
        print "processing line %10d\r" % line_count if options[:verbose]
        next  if  line =~ options[:comment_regexp]  # ignore all comment lines if there are any

        # cater for the quoted csv data containing the row separator carriage return character
        # in which case the row data will be split across multiple lines (see the sample content in spec/fixtures/carriage_returns_rn.csv)
        # by detecting the existence of an uneven number of quote characters
        while line.count(options[:quote_char])%2 == 1
          print "line contains uneven number of quote chars so including content of next line" if options[:verbose]
          line += f.readline
        end

        line.chomp!    # will use $/ which is set to options[:col_sep]

        if (line =~ %r{#{options[:quote_char]}}) and (! options[:force_simple_split])
          dataA = CSV.parse( line, csv_options ).flatten.collect!{|x| x.nil? ? '' : x} # to deal with nil values from CSV.parse
        else
          dataA =  line.split(options[:col_sep])
        end
        dataA.map!{|x| x.gsub(%r/options[:quote_char]/,'') }
        dataA.map!{|x| x.strip}  if options[:strip_whitespace]
        hash = Hash.zip(headerA,dataA)  # from Facets of Ruby library
        # make sure we delete any key/value pairs from the hash, which the user wanted to delete:
        # Note: Ruby < 1.9 doesn't allow empty symbol literals!
        hash.delete(nil); hash.delete('');
        if RUBY_VERSION.to_f > 1.8
          eval('hash.delete(:"")')
        end

        # remove empty values using the same regexp as used by the rails blank? method
        # which caters for double \n and \r\n characters such as "1\r\n\r\n2" whereas the original check (v =~ /^\s*$/) does not
        hash.delete_if{|k,v| v.nil? || v !~ /[^[:space:]]/}  if options[:remove_empty_values]

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
        next if hash.empty? if options[:remove_empty_hashes]

        if use_chunks
          chunk << hash  # append temp result to chunk

          if chunk.size >= chunk_size || f.eof?   # if chunk if full, or EOF reached
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
      $/ = old_row_sep   # make sure this stupid global variable is always reset to it's previous value after we're done!
    end
    if block_given?
      return chunk_count  # when we do processing through a block we only care how many chunks we processed
    else
      return result # returns either an Array of Hashes, or an Array of Arrays of Hashes (if in chunked mode)
    end
  end

#  def SmarterCSV.process_csv(*args)
#    warn "[DEPRECATION] `process_csv` is deprecated.  Please use `process` instead."
#    SmarterCSV.process(*args)
#  end

  private
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

  # limitation: this currently reads the whole file in before making a decision
  def self.guess_line_ending( filehandle, options )
    counts = {"\n" => 0 , "\r" => 0, "\r\n" => 0}
    quoted_char = false

    # count how many of the pre-defined line-endings we find
    # ignoring those contained within quote characters
    filehandle.each_char do |c|
      quoted_char = !quoted_char if c == options[:quote_char]
                             # Skip invalid byte sequence in UTF-8
      next if quoted_char || begin c !~ /\r|\n|\r\n/ rescue true end
      counts[c] += 1
    end
    # find the key/value pair with the largest counter:
    k,v = counts.max_by{|k,v| v}
    return k                    # the most frequent one is it
  end
end

