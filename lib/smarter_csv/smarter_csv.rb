module SmarterCSV
  # this reads and processes a "generalized" CSV file and returns the contents either as an Array of Hashes,
  # or an Array of Arrays, which contain Hashes, or processes Chunks of Hashes via a given block
  #
  # File.read_csv supports the following options:
  #  * :col_sep : column separator , which defaults to ','
  #  * :row_sep : row separator or record separator , defaults to system's $/ , which defaults to "\n"
  #  * :quote_char : quotation character , defaults to '"' (currently not used)
  #  * :comment_regexp : regular expression which matches comment lines , defaults to /^#/ (see NOTE about the CSV header)
  #  * :chunk_size : if set, determines the desired chunk-size (defaults to nil, no chunk processing)
  #  * :remove_empty_fields : remove fields which have nil or empty strings as values (default: true)
  #
  # NOTES about CSV Headers:
  #  - as this method parses CSV files, it is assumed that the first line of any file will contain a valid header
  #  - the first line with the CSV header may or may not be commented out according to the :comment_regexp
  #  - any occurences of :comment_regexp or :row_sep will be stripped from the first line with the CSV header
  #  - any of the keys in the header line will be converted to Ruby symbols before being used in the returned Hashes
  #
  # NOTES on Key Mapping:
  #  - keys in the header line of the file can be re-mapped to a chosen set of symbols, so the resulting Hashes
  #    can be better used internally in our application (e.g. when directly creating MongoDB entries with them)
  #  - if you want to completely delete a key, then map it to nil or to '', they will be automatically deleted from any result Hash
  #
  # NOTES on the use of Chunking and Blocks:
  #  - chunking can be VERY USEFUL if used in combination with passing a block to File.read_csv FOR LARGE FILES
  #  - if you pass a block to File.read_csv, that block will be executed and given an Array of Hashes as the parameter.
  #    If the chunk_size is not set, then the array will only contain one Hash.
  #    If the chunk_size is > 0 , then the array may contain up to chunk_size Hashes.
  #    This can be very useful when passing chunked data to a post-processing step, e.g. through Resque
  #

  def SmarterCSV.process(filename, options={}, &block)
    default_options = {:col_sep => ',' , :row_sep => $/ , :quote_char => '"',
      :remove_empty_fields => true, :remove_zero_fields => false , :remove_fields_matching => nil , :remove_empty_hashes => true ,
      :comment_regexp => /^#/, :chunk_size => nil , :key_mapping_hash => nil , :downcase_header => true, :strings_as_keys => false 
    }
    options = default_options.merge(options)
    headerA = []
    result = []
    old_row_sep = $/
    begin
      $/ = options[:row_sep]
      f = File.open(filename, "r")
      
      # process the header line in the CSV file..
      # the first line of a CSV file contains the header .. it might be commented out, so we need to read it anyhow
      headerA = f.readline.sub(options[:comment_regexp],'').chomp(options[:row_sep]).split(options[:col_sep]).map{|x| x.gsub(%r/options[:quote_char]/,'').gsub(/\s+/,'_')}
      headerA.map!{|x| x.downcase }   if options[:downcase_header]
      headerA.map!{|x| x.to_sym } unless options[:strings_as_keys]
      key_mappingH = options[:key_mapping]
      
      # do some key mapping on the keys in the file header
      #   if you want to completely delete a key, then map it to nil or to ''
      if ! key_mappingH.nil? && key_mappingH.class == Hash && key_mappingH.keys.size > 0
        headerA.map!{|x| key_mappingH.has_key?(x) ? (key_mappingH[x].nil? ? nil : key_mappingH[x].to_sym) : x}
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
        next  if  line =~ options[:comment_regexp]  # ignore all comment lines if there are any
        line.chomp!    # will use $/ which is set to options[:col_sep]
        
        dataA = line.split(options[:col_sep])
        hash = Hash.zip(headerA,dataA)  # from Facets of Ruby library
        # make sure we delete any key/value pairs from the hash, which the user wanted to delete:
        hash.delete(nil); hash.delete(''); hash.delete(:"") # delete any hash keys which were mapped to be deleted
        hash.delete_if{|k,v| v.nil? || v =~ /^\s*$/}  if options[:remove_empty_fields]
        hash.delete_if{|k,v| ! v.nil? && v =~ /^(\d+|\d+\.\d+)$/ && v.to_f == 0} if options[:remove_zero_fields]   # values are typically Strings!
        hash.delete_if{|k,v| v =~ options[:remove_fields_matching]} if options[:remove_fields_matching]
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
    ensure
      $/ = old_row_sep   # make sure this stupid global variable is always reset to it's previous value after we're done!
    end
    if block_given?
      return chunk_count  # when we do processing through a block we only care how many chunks we processed
    else
      return result # returns either an Array of Hashes, or an Array of Arrays of Hashes (if in chunked mode)
    end
  end

  def SmarterCSV.process_csv(*args)
    warn "[DEPRECATION] `process_csv` is deprecated.  Please use `process` instead."
    SmarterCSV.process(*args)
  end
end

