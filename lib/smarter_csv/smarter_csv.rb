
module SmarterCSV
  class SmarterCSVException < StandardError; end
  class HeaderSizeMismatch < SmarterCSVException; end
  class IncorrectOption < SmarterCSVException; end
  class DuplicateHeaders < SmarterCSVException; end
  class MissingHeaders < SmarterCSVException; end
  class ObsoleteOptions < SmarterCSVException; end

  def self.errors
    @errors
  end
  def self.errors=(value)
    @errors = value
  end

  def self.warnings
    @warnings
  end
  def self.warnings=(value)
    @warnings = value
  end

  def self.process(input, given_options={}, &block)   # first parameter: filename or input object with readline method
    # @errors is  where validation errors get accumulated into - similar to ActiveRecord validations, but with additional keys
    # @errors[ file_line_no ] << 'invalid value for :employee_id in line 17'
    # @errors[ file_line_no ] << 'missing required field :email in line 193'
    # @errors[ :header ] << 'duplicate header :email'
    # @errors[ :base ] << 'did not find :email for all data rows'
    # @warnings[ file_line_no ] << 'line 23 did not contain data'
    #
    @errors = {}
    @warnings = {}
    @counters = {}

    options = process_options(given_options)

    csv_options = options.select{|k,v| [:col_sep, :row_sep, :quote_char].include?(k)} # options.slice(:col_sep, :row_sep, :quote_char)

    headerA = []
    result = []
    old_row_sep = $/
    @file_line_count = 0
    @csv_line_count = 0
    @has_rails = !! defined?(Rails)

    begin
      f = input.respond_to?(:readline) ? input : File.open(input, "r:#{options[:file_encoding]}")

      if (options[:force_utf8] || options[:file_encoding] =~ /utf-8/i) && ( f.respond_to?(:external_encoding) && f.external_encoding != Encoding.find('UTF-8') || f.respond_to?(:encoding) && f.encoding != Encoding.find('UTF-8') )
        puts 'WARNING: you are trying to process UTF-8 input, but did not open the input with "b:utf-8" option. See README file "NOTES about File Encodings".'
      end

      if options[:row_sep].to_s == 'auto'
        options[:row_sep] = line_ending = SmarterCSV.guess_line_ending( f, options )
        f.rewind
      end
      $/ = options[:row_sep]

      if options[:skip_lines].to_i > 0
        options[:skip_lines].to_i.times do
          f.readline
          @file_line_count += 1
        end
      end

      # if headers are in the file, we need to process them...

      if options[:headers_in_file] # extract the header line
        # process the header line in the CSV file..
        # the first line of a CSV file contains the header .. it might be commented out, so we need to read it anyhow
        header = f.readline
        puts "Raw headers:\n#{header}\n" if options[:verbose]
        @file_line_count += 1
        @csv_line_count += 1
        header = header.force_encoding('utf-8').encode('utf-8', invalid: :replace, undef: :replace, replace: options[:invalid_byte_sequence]) if options[:force_utf8] || options[:file_encoding] !~ /utf-8/i
        header = header.sub(options[:comment_regexp],'').chomp(options[:row_sep])

        if (header =~ %r{#{options[:quote_char]}}) and (! options[:force_simple_split])
          file_headerA = begin
            CSV.parse( header, **csv_options ).flatten.collect!{|x| x.nil? ? '' : x} # to deal with nil values from CSV.parse
          rescue CSV::MalformedCSVError => e
            raise $!, "#{$!} [SmarterCSV: csv line #{@csv_line_count}]", $!.backtrace
          end
        else
          file_headerA =  header.split(options[:col_sep])
        end

        puts "Split headers:\n#{pp(file_headerA)}\n" if options[:verbose]

        # do the header transformations the user requested:
        if options[:header_transformations]
          options[:header_transformations].each do |transformation|
            if transformation.is_a?(Symbol)
              file_headerA = self.public_send( transformation, file_headerA )
            elsif transformation.is_a?(Hash)
              trans, args = transformation.first
              file_headerA = self.public_send( trans, file_headerA, args )
            elsif transformation.is_a?(Array)
              trans, args = transformation
              file_headerA = self.public_send( trans, file_headerA, args )
            else
              file_headerA = transformation.call( file_headerA )
            end
          end
        end

        puts "Transformed headers:\n#{pp(file_headerA)}\n" if options[:verbose]

        file_header_size = file_headerA.size
      else
        raise SmarterCSV::IncorrectOption , "ERROR: If :headers_in_file is set to false, you have to provide :user_provided_headers" if options[:user_provided_headers].nil?
      end

      # if the user provides the headers, and they replace an existing header, then check they have the same size
      # otherwise use the header we found/transformed above

      if options[:user_provided_headers] && options[:user_provided_headers].class == Array && ! options[:user_provided_headers].empty?
        # use user-provided headers
        headerA = options[:user_provided_headers]
        if defined?(file_header_size) && ! file_header_size.nil?
          if headerA.size != file_header_size
            raise SmarterCSV::HeaderSizeMismatch , "ERROR: :user_provided_headers defines #{headerA.size} headers !=  CSV-file #{input} has #{file_header_size} headers"
          else
            # we could print out the mapping of file_headerA to headerA here
          end
        end
      else
        headerA = file_headerA
      end

      puts "Effective headers:\n#{pp(headerA)}\n" if options[:verbose]

      # header_validations on headerA

      # do the header validations the user requested:
      # Header validations typically raise errors directly
      if options[:header_validations]
        options[:header_validations].each do |validation|
          if validation.is_a?(Symbol)
            self.public_send( validation, headerA )
          elsif validation.is_a?(Hash)
            val, args = validation.first
            self.public_send( val, headerA, args )
          elsif validation.is_a?(Array)
            val, args = validation
            self.public_send( val, headerA, args )
          else
            validation.call( headerA ) unless validation.nil?
          end
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

      # instead of readline, which accumulates the lines in an array, we should use `open.each_line` for large files, which only returns one line at a time

      while ! f.eof?    # we can't use f.readlines() here, because this would read the whole file into memory at once, and eof => true
        line = f.readline  # read one line.. this uses the input_record_separator $/ which we set previously!

        # replace invalid byte sequence in UTF-8 with question mark to avoid errors
        line = line.force_encoding('utf-8').encode('utf-8', invalid: :replace, undef: :replace, replace: options[:invalid_byte_sequence]) if options[:force_utf8] || options[:file_encoding] !~ /utf-8/i

        @file_line_count += 1
        @csv_line_count += 1
        print "processing file line %10d, csv line %10d\r" % [@file_line_count, @csv_line_count] if options[:verbose]
        next if line =~ options[:comment_regexp] # ignore all comment lines if there are any



        # cater for the quoted csv data containing the row separator carriage return character
        # in which case the row data will be split across multiple lines (see the sample content in spec/fixtures/carriage_returns_rn.csv)
        # by detecting the existence of an uneven number of quote characters
        multiline = line.count(options[:quote_char])%2 == 1
        while line.count(options[:quote_char])%2 == 1
          next_line = f.readline
          next_line = next_line.force_encoding('utf-8').encode('utf-8', invalid: :replace, undef: :replace, replace: options[:invalid_byte_sequence]) if options[:force_utf8] || options[:file_encoding] !~ /utf-8/i
          line += next_line
          @file_line_count += 1
        end
        print "\nline contains uneven number of quote chars so including content through file line %d\n" % @file_line_count if options[:verbose] && multiline

        line.chomp!    # will use $/ which is set to options[:col_sep]
        next if line.empty? || line =~ /\A\s*\z/

        if (line =~ %r{#{options[:quote_char]}}) and (! options[:force_simple_split])
          dataA = begin
            CSV.parse( line, **csv_options ).flatten.collect!{|x| x.nil? ? '' : x} # to deal with nil values from CSV.parse
          rescue CSV::MalformedCSVError => e
            raise $!, "#{$!} [SmarterCSV: csv line #{@csv_line_count}]", $!.backtrace
          end
        else
          dataA =  line.split(options[:col_sep])
        end

        # do the data transformations the user requested:
        if options[:data_transformations]
          options[:data_transformations].each do |transformation|
            if transformation.is_a?(Symbol)
              dataA = self.public_send( transformation, dataA )
            elsif transformation.is_a?(Hash)
              trans, args = transformation.first
              dataA = self.public_send( trans, dataA, args )
            elsif transformation.is_a?(Array)
              trans, args = transformation
              dataA = self.public_send( trans, dataA, args )
            else
              dataA = transformation.call( dataA )
            end
          end
        end

        # if a row in the CSV does not contain any data, we'll ignore it, but issue a warning:
        if dataA.empty?
          @warnings[ @file_line_count ] ||= []
          @warnings[ @file_line_count ] << "No data in line #{@file_line_count}"
          next
        end

        # vvv THIS LOOKS TO BE REDUNDANT -----------------------------------------------
        #
        # anything which could be validated here, could be better validated with hash_validations,
        # because validations typically depend on the column name
        #
        # do the data validations the user requested:
        data_validation_errors = 0
        if options[:data_validations]
          options[:data_validations].each do |validation|
            if validation.is_a?(Symbol)
              data_validation_errors += self.public_send( validation, dataA )
            elsif validation.is_a?(Hash)
              trans, args = validation.first
              data_validation_errors += self.public_send( trans, dataA, args )
            elsif validation.is_a?(Array)
              trans, args = validation
              data_validation_errors += self.public_send( trans, dataA, args )
            else
              data_validation_errors += validation.call( dataA )
            end
          end
        end
        next if data_validation_errors > 0 # ignore lines with data_validation errors
        #
        # ^^^ THIS LOOKS TO BE REDUNDANT -----------------------------------------------


        hash = Hash.zip(headerA,dataA)  # from Facets of Ruby library

        # make sure we delete any key/value pairs from the hash, which the user wanted to delete..
        # e.g. if any keys which are mapped to nil or an empty string
        # Note: Ruby < 1.9 doesn't allow empty symbol literals!
        hash.delete(nil); hash.delete('');
        if RUBY_VERSION.to_f > 1.8
          eval('hash.delete(:"")')
        end

        # do the hash transformations the user requested:
        if options[:hash_transformations]
          options[:hash_transformations].each do |transformation|
            if transformation.is_a?(Symbol)
              hash = self.public_send( transformation, hash )
            elsif transformation.is_a?(Hash)
              trans, args = transformation.first
              hash = self.public_send( trans, hash, args )
            elsif transformation.is_a?(Array)
              trans, args = transformation
              hash = self.public_send( trans, hash, args )
            else
              hash = transformation.call( hash )
            end
          end
        end

        # do the hash validations the user requested:
        hash_validation_errors = 0
        if options[:hash_validations]
          options[:hash_validations].each do |validation|
            if validation.is_a?(Symbol)
              hash_validation_errors += self.public_send( validation, hash )
            elsif validation.is_a?(Hash)
              trans, args = validation.first
              hash_validation_errors += self.public_send( trans, hash, args )
            elsif validation.is_a?(Array)
              trans, args = validation
              hash_validation_errors += self.public_send( trans, hash, args )
            else
              hash_validation_errors += validation.call( hash )
            end
          end
        end
        next if hash_validation_errors > 0 # ignore lines with hash_validation errors

        puts "CSV Line #{@file_line_count}: #{pp(hash)}" if options[:verbose]

        next if hash.empty? if options[:remove_empty_hashes]

        # process the chunks or the resulting hash

        if use_chunks
          chunk << hash  # append temp result to chunk

          if chunk.size >= chunk_size || f.eof?   # if chunk if full, or EOF reached = last chunk
            # do something with the chunk
            if block_given?
              yield chunk  # do something with the hashes in the chunk in the block
            else
              result << chunk  # not sure yet, why anybody would want to do this without a block - not a good idea to accumulate an array
            end
            chunk_count += 1
            chunk = []  # initialize for next chunk of data

          else
            # keep accumulating lines for the chunk
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
      $/ = old_row_sep   # make sure this stupid global variable is always reset to it's previous value after we're done!
      f.close
    end

    # What is the best way to surface validation @errors and @warnings in either of the two scenarios:

    if block_given?
      return chunk_count, @csv_line_count # when we do processing through a block we only care how many chunks we processed
    else
      return result # returns either an Array of Hashes, or an Array of Arrays of Hashes (if in chunked mode)
    end
  end


  private

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
          counts["\r"] += 1  # \r are counted after they appeared, we might
        end
      elsif c == "\n"
        counts["\n"] += 1
      end
      last_char = c
      lines += 1
      break if options[:auto_row_sep_chars] && options[:auto_row_sep_chars] > 0 && lines >= options[:auto_row_sep_chars]
    end
    counts["\r"] += 1 if last_char == "\r"
    # find the key/value pair with the largest counter:
    k,_ = counts.max_by{|_,v| v}
    return k                    # the most frequent one is it
  end
end
