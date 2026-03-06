# frozen_string_literal: true

require 'set'

module SmarterCSV
  class Reader
    include Enumerable

    # Default chunk size used by each_chunk when chunk_size is not explicitly set.
    # A warning is emitted to STDERR so users know to configure it explicitly.
    DEFAULT_CHUNK_SIZE = 100

    include ::SmarterCSV::Options
    include ::SmarterCSV::FileIO
    include ::SmarterCSV::AutoDetection
    include ::SmarterCSV::Headers
    include ::SmarterCSV::HeaderTransformations
    include ::SmarterCSV::HeaderValidations
    include ::SmarterCSV::HashTransformations
    include ::SmarterCSV::Parser

    attr_reader :input, :options
    attr_reader :csv_line_count, :chunk_count, :file_line_count
    attr_reader :enforce_utf8, :has_rails, :has_acceleration
    attr_reader :errors, :warnings, :headers, :raw_header, :result

    # rubocop:disable Naming/MethodName
    def headerA
      warn "Deprecarion Warning: 'headerA' will be removed in future versions. Use 'headders'"
      @headerA
    end
    # rubocop:enable Naming/MethodName

    # first parameter: filename or input object which responds to readline method
    def initialize(input, given_options = {})
      @input = input
      @has_rails = !!defined?(Rails)
      @csv_line_count = 0
      @chunk_count = 0
      @errors = {}
      @file_line_count = 0
      @headerA = []
      @headers = nil
      @raw_header = nil # header as it appears in the file
      @result = []
      @warnings = {}
      @enforce_utf8 = false # only set to true if needed (after options parsing)
      @options = process_options(given_options)
      # true if it is compiled with accelleration
      @has_acceleration = !!SmarterCSV::Parser.respond_to?(:parse_csv_line_c)
    end

    # Yields each successfully parsed row as a Hash.
    # Ignores chunk_size — always row-by-row, enabling standard Enumerable usage.
    # Returns an Enumerator when called without a block.
    #
    # Examples:
    #   reader.each { |hash| MyModel.upsert(hash) }
    #   reader.each_with_index { |hash, i| puts "Row #{i}: #{hash}" }
    #   reader.select { |h| h[:country] == "US" }
    #   reader.lazy.map { |h| h[:name] }.first(10)
    def each
      return enum_for(:each) unless block_given?

      # Force row-by-row mode regardless of chunk_size setting
      original_chunk_size = @options[:chunk_size]
      @options[:chunk_size] = nil
      process { |row_array, _| yield row_array.first }
    ensure
      @options[:chunk_size] = original_chunk_size
    end

    # Yields each chunk as Array<Hash> plus its 0-based chunk index.
    # Uses chunk_size from options; raises ArgumentError if chunk_size < 1.
    # Returns an Enumerator when called without a block.
    #
    # Examples:
    #   reader = SmarterCSV::Reader.new("big.csv", chunk_size: 500)
    #   reader.each_chunk { |chunk, i| Sidekiq.push_bulk(chunk) }
    #   reader.each_chunk.with_index { |chunk, i| puts "Chunk #{i}: #{chunk.size} rows" }
    def each_chunk
      return enum_for(:each_chunk) unless block_given?

      chunk_size = @options[:chunk_size]
      if chunk_size.nil?
        warn "SmarterCSV: chunk_size not set, defaulting to #{DEFAULT_CHUNK_SIZE}. Set chunk_size explicitly to suppress this warning." unless @options[:verbose] == :quiet
        chunk_size = DEFAULT_CHUNK_SIZE
      end
      unless chunk_size.is_a?(Integer) && chunk_size >= 1
        raise ArgumentError, "chunk_size must be an Integer >= 1 (got #{chunk_size.inspect})"
      end

      # Temporarily apply chunk_size (handles nil default case) and restore after
      original_chunk_size = @options[:chunk_size]
      @options[:chunk_size] = chunk_size
      begin
        # process reuses the same chunk Array (clearing it after each yield),
        # so we dup to give callers a stable snapshot they can safely store.
        process { |chunk, index| yield chunk.dup, index }
      ensure
        @options[:chunk_size] = original_chunk_size
      end
    end

    def process(&block) # rubocop:disable Lint/UnusedMethodArgument
      @enforce_utf8 = options[:force_utf8] || options[:file_encoding] !~ /utf-8/i
      @verbose = options[:verbose]

      begin
        fh = input.respond_to?(:readline) ? input : File.open(input, "r:#{options[:file_encoding]}")

        if (options[:force_utf8] || options[:file_encoding] =~ /utf-8/i) && (fh.respond_to?(:external_encoding) && fh.external_encoding != Encoding.find('UTF-8') || fh.respond_to?(:encoding) && fh.encoding != Encoding.find('UTF-8'))
          warn 'WARNING: you are trying to process UTF-8 input, but did not open the input with "b:utf-8" option. See README file "NOTES about File Encodings".' unless options[:verbose] == :quiet
        end

        # auto-detect the row separator
        options[:row_sep] = guess_line_ending(fh, options) if options[:row_sep]&.to_sym == :auto
        # attempt to auto-detect column separator
        options[:col_sep] = guess_column_separator(fh, options) if options[:col_sep]&.to_sym == :auto

        skip_lines(fh, options)

        # NOTE: we are no longer using header_size
        @headers, _header_size = process_headers(fh, options)
        @headerA = @headers # @headerA is deprecated, use @headers

        $stderr.puts "Effective headers:\n#{pp(@headers)}\n" if @verbose == :debug

        header_validations(@headers, options)

        # Precompute column filter sets for only_headers / except_headers (O(1) lookup per row)
        @only_headers_set   = options[:only_headers]   ? Set.new(options[:only_headers])   : nil
        @except_headers_set = options[:except_headers] ? Set.new(options[:except_headers]) : nil

        # Precompute positional boolean array for the C extension so it can do O(1) per-field
        # checks instead of calling rb_ary_includes (O(k)) for every column on every row.
        if @only_headers_set || @except_headers_set
          options[:_keep_cols] = @headers.map do |h|
            @only_headers_set ? @only_headers_set.include?(h) : !@except_headers_set.include?(h)
          end
        end

        # Precompute all hot-path strategy ivars once — eliminates per-row option lookups
        # and method-dispatch overhead in the main loop.
        #
        # @quote_escaping_backslash / @quote_escaping_double may already exist if
        # parse_with_auto_fallback ran during header parsing (lazily created there).
        # Ensure they exist and carry the now-final _keep_cols bitmap.
        @quote_escaping_backslash ||= options.merge(quote_escaping: :backslash)
        @quote_escaping_double    ||= options.merge(quote_escaping: :double_quotes)
        @quote_escaping_backslash[:_keep_cols] = options[:_keep_cols] # nil when no filtering
        @quote_escaping_double[:_keep_cols]    = options[:_keep_cols]

        @quote_escaping_auto = options[:quote_escaping] == :auto
        @use_acceleration    = options[:acceleration] && has_acceleration

        # The single options hash used on the hot path — for :auto we always try backslash
        # first (C downgrades to RFC internally via Opt #5 when no backslash is found).
        @hot_path_options = @quote_escaping_auto ? @quote_escaping_backslash : options

        # Key-cleanup flags — computed once, checked per row via cheap ivar reads.
        # hash.delete(nil) / hash.delete('') only occur when key_mapping maps a header to nil/"".
        # hash.delete(:"") also catches empty headers produced by ,, in the CSV.
        @delete_nil_keys   = !!options[:key_mapping]
        @delete_empty_keys = !!options[:key_mapping] || @headers.include?(:"")

        # Cache quote_char as an ivar for the stitch-loop memchr guard (avoids hash lookup per continuation line).
        @quote_char = options[:quote_char]
        # Cache field_size_limit as an ivar (nil when unset → one nil-check per row, no method calls).
        @field_size_limit = options[:field_size_limit]

        # in case we use chunking.. we'll need to set it up..
        if options[:chunk_size].to_i > 0
          use_chunks = true
          chunk_size = options[:chunk_size].to_i
          @chunk_count = 0
          chunk = []
        else
          use_chunks = false
        end

        # --- INSTRUMENTATION HOOKS ---
        # on_start / on_chunk / on_complete are optional callables (nil by default).
        # Hooks only fire from `process` (library-controlled iteration). Enumerator
        # modes (each / each_chunk) do not fire hooks — the caller owns the lifecycle.
        _on_start    = options[:on_start]
        _on_chunk    = options[:on_chunk]
        _on_complete = options[:on_complete]
        _start_time  = Process.clock_gettime(Process::CLOCK_MONOTONIC) if _on_start || _on_complete

        if _on_start
          _input_meta = if @input.is_a?(String)
                          { input: @input, file_size: (File.size(@input) rescue nil) }
                        else
                          { input: @input.class.name, file_size: nil }
                        end
          _on_start.call(_input_meta.merge(col_sep: options[:col_sep], row_sep: options[:row_sep]))
        end

        # now on to processing all the rest of the lines in the CSV file:
        while (line = next_line_with_counts(fh, options))

          # replace invalid byte sequence in UTF-8 with question mark to avoid errors
          line = enforce_utf8_encoding(line, options) if @enforce_utf8

          $stderr.print "processing file line %10d, csv line %10d\r" % [@file_line_count, @csv_line_count] if @verbose == :debug

          next if options[:comment_regexp] && line =~ options[:comment_regexp] # ignore all comment lines if there are any

          # Snapshot line counters before multiline stitching so error records reflect
          # where the bad row started, not where it failed.
          bad_row_start_csv_line  = @csv_line_count
          bad_row_start_file_line = @file_line_count

          begin
            # --- PARSE (inlined — no method-wrapper overhead on the hot path) ---
            # Replaces: process_line_to_hash → parse_line_to_hash → parse_line_to_hash_auto
            # All routing decisions are pre-baked into ivars set up after header processing.
            if @use_acceleration
              hash, data_size = parse_line_to_hash_c(line, @headers, @hot_path_options)
              # :auto only: if unclosed quote AND backslash present, RFC may close it differently
              if @quote_escaping_auto && data_size == -1 && line.include?('\\')
                hash, data_size = parse_line_to_hash_c(line, @headers, @quote_escaping_double)
              end
            else
              has_quotes = line.include?(options[:quote_char])
              hash, data_size = parse_line_to_hash_ruby(line, @headers, @hot_path_options, has_quotes)
              if @quote_escaping_auto && data_size == -1 && line.include?('\\')
                hash, data_size = parse_line_to_hash_ruby(line, @headers, @quote_escaping_double, has_quotes)
              end
            end

            # --- MULTILINE STITCH ---
            # data_size == -1 means the parser saw an unclosed quoted field at end-of-line.
            # Fetch the next physical line, append, and re-parse until the field closes.
            while data_size == -1
              next_line = fh.gets(options[:row_sep])
              raise MalformedCSV, "Unclosed quoted field detected in multiline data" if next_line.nil?

              next_line = enforce_utf8_encoding(next_line, options) if @enforce_utf8
              line += next_line
              @file_line_count += 1
              $stderr.print "\nline contains unclosed quoted field, including content through file line %d\n" % @file_line_count if @verbose == :debug

              # DoS guard: prevent runaway multiline accumulation (vectors: never-closing quote, huge embedded content)
              if @field_size_limit && line.bytesize > @field_size_limit
                raise SmarterCSV::FieldSizeLimitExceeded,
                      "Multiline field exceeds field_size_limit of #{@field_size_limit} bytes " \
                      "(accumulated #{line.bytesize} bytes)"
              end

              # Opt #8 (memchr guard): if the newly appended line contains no quote character,
              # it cannot close the currently open quoted field — skip the full re-parse and
              # keep accumulating physical lines.  String#include? uses memchr internally (C speed).
              next unless next_line.include?(@quote_char)

              if @use_acceleration
                # :nocov:
                hash, data_size = parse_line_to_hash_c(line, @headers, @hot_path_options)
                if @quote_escaping_auto && data_size == -1 && line.include?('\\')
                  hash, data_size = parse_line_to_hash_c(line, @headers, @quote_escaping_double)
                end
                # :nocov:
              else
                # Optimization #18: use detect_multiline as a cheap gate before attempting a full
                # Ruby re-parse on the growing stitched line. detect_multiline_strict now uses
                # byteindex skip-ahead (Opt #17) and is faster than parse_line_to_hash_ruby on
                # the same content. Saves N-2 wasted full parses per multiline row.
                next if detect_multiline(line, options)

                has_quotes = true # we know the line has quotes — we've been stitching a quoted field
                hash, data_size = parse_line_to_hash_ruby(line, @headers, @hot_path_options, has_quotes)
                if @quote_escaping_auto && data_size == -1 && line.include?('\\')
                  hash, data_size = parse_line_to_hash_ruby(line, @headers, @quote_escaping_double, has_quotes)
                end
              end
            end

            # --- EXTRA COLUMNS ---
            if data_size > @headers.size
              raise SmarterCSV::HeaderSizeMismatch, "extra columns detected on line #{@file_line_count}" if options[:missing_headers] == :raise

              while @headers.size < data_size
                @headers << "#{options[:missing_header_prefix]}#{@headers.size + 1}".to_sym
              end
            end

            next if hash.nil?

            # --- FIELD SIZE LIMIT CHECK ---
            # Pre-filter: if the raw line fits within the limit, no individual field can exceed it
            # (a field is always a substring of its row). Only iterate over values for large rows.
            if @field_size_limit && line.bytesize > @field_size_limit
              hash.each_value do |v|
                if v.is_a?(String) && v.bytesize > @field_size_limit
                  raise SmarterCSV::FieldSizeLimitExceeded,
                        "Field exceeds field_size_limit of #{@field_size_limit} bytes (got #{v.bytesize} bytes)"
                end
              end
            end

            # --- COLUMN SELECTION ---
            hash.select! { |k, _| @only_headers_set.include?(k) }   if @only_headers_set
            hash.reject! { |k, _| @except_headers_set.include?(k) } if @except_headers_set

            # --- HASH CLEANUP & TRANSFORMATIONS ---
            if @use_acceleration
              # C already applied: remove_empty_values, convert_values_to_numeric, remove_zero_values.
              # Remove nil/"" keys left by key_mapping or empty CSV headers.
              if @delete_nil_keys
                hash.delete(nil)
                hash.delete('')
              end
              hash.delete(:"") if @delete_empty_keys

              if (matcher = options[:nil_values_matching])
                if options[:remove_empty_values]
                  hash.delete_if do |_k, v|
                    str_val = v.is_a?(String) ? v : (v.is_a?(Numeric) ? v.to_s : nil)
                    str_val && matcher.match?(str_val)
                  end
                else
                  hash.each_key do |k|
                    v = hash[k]
                    str_val = v.is_a?(String) ? v : (v.is_a?(Numeric) ? v.to_s : nil)
                    hash[k] = nil if str_val && matcher.match?(str_val)
                  end
                end
              end

              if options[:value_converters]
                options[:value_converters].each do |key, converter|
                  hash[key] = converter.convert(hash[key]) if hash.key?(key)
                end
              end
            else
              hash = hash_transformations(hash, options)
            end

            next if options[:remove_empty_hashes] && hash.empty?

            $stderr.puts "CSV Line #{@file_line_count}: #{pp(hash)}" if @verbose == :debug
            # optional adding of csv_line_number to the hash to help debugging
            hash[:csv_line_number] = @csv_line_count if options[:with_line_numbers]
          rescue SmarterCSV::Error, EOFError => e
            raise if options[:on_bad_row] == :raise

            handle_bad_row(e, line, bad_row_start_csv_line, bad_row_start_file_line, options)
            next
          end

          # process the chunks or the resulting hash
          if use_chunks
            chunk << hash # append temp result to chunk

            if chunk.size >= chunk_size || fh.eof? # if chunk if full, or EOF reached
              _on_chunk&.call({ chunk_number: @chunk_count + 1, rows_in_chunk: chunk.size, total_rows_so_far: @csv_line_count })
              # do something with the chunk
              if block_given?
                yield chunk, @chunk_count # do something with the hashes in the chunk in the block
              else
                @result << chunk.dup # Append chunk to result (use .dup to keep a copy after we do chunk.clear)
              end
              @chunk_count += 1
              chunk.clear # re-initialize for next chunk of data
            else
              # the last chunk may contain partial data, which is handled below
            end
            # while a chunk is being filled up we don't need to do anything else here

          else # no chunk handling
            if block_given?
              yield [hash], @chunk_count # do something with the hash in the block (better to use chunking here)
              @chunk_count += 1
            else
              @result << hash
            end
          end
        end

        # print new line to retain last processing line message
        $stderr.print "\n" if @verbose == :debug

        # handling of last chunk:
        if !chunk.nil? && chunk.size > 0
          _on_chunk&.call({ chunk_number: @chunk_count + 1, rows_in_chunk: chunk.size, total_rows_so_far: @csv_line_count })
          # do something with the chunk
          if block_given?
            yield chunk, @chunk_count # do something with the hashes in the chunk in the block
          else
            @result << chunk.dup # Append chunk to result (use .dup to keep a copy after we do chunk.clear)
          end
          @chunk_count += 1
          # chunk = [] # initialize for next chunk of data
        end

        if _on_complete
          _on_complete.call({
            total_rows:   @csv_line_count,
            total_chunks: @chunk_count,
            duration:     Process.clock_gettime(Process::CLOCK_MONOTONIC) - _start_time,
            bad_rows:     @errors[:bad_row_count] || 0,
          })
        end
      ensure
        fh.close if fh.respond_to?(:close)
      end

      if block_given?
        @chunk_count # when we do processing through a block we only care how many chunks we processed
      else
        @result # returns either an Array of Hashes, or an Array of Arrays of Hashes (if in chunked mode)
      end
    end

    def count_quote_chars(line, quote_char, col_sep = ",", quote_escaping = :double_quotes)
      return 0 if line.nil? || quote_char.nil? || quote_char.empty?

      # Use C extension for performance if available (avoids creating a String object per character)
      if @has_acceleration && SmarterCSV::Parser.respond_to?(:count_quote_chars_c)
        return SmarterCSV::Parser.count_quote_chars_c(line, quote_char, col_sep, quote_escaping == :backslash)
      end

      # Fallback to Ruby implementation
      if quote_escaping == :backslash
        # Backslash mode: must walk character-by-character to track escape state
        count = 0
        escaped = false

        line.each_char do |char|
          if char == '\\' && !escaped
            escaped = true
          else
            if char == quote_char && !escaped
              count += 1
            end
            escaped = false
          end
        end
        count
      else
        # Optimization #3: double_quotes mode — use String#count (single C call,
        # no per-character String allocation)
        line.count(quote_char)
      end
    end

    # Returns [escaped_count, rfc_count] for :auto mode dual counting.
    # escaped_count: quote chars not preceded by odd backslashes
    # rfc_count: all quote chars (backslash has no special meaning)
    def count_quote_chars_auto(line, quote_char, col_sep = ",")
      return [0, 0] if line.nil? || quote_char.nil? || quote_char.empty?

      if @has_acceleration && SmarterCSV::Parser.respond_to?(:count_quote_chars_auto_c)
        return SmarterCSV::Parser.count_quote_chars_auto_c(line, quote_char, col_sep)
      end

      # Optimization #3: rfc_count uses String#count (single C call)
      rfc_count = line.count(quote_char)

      # Optimization #9: if no backslashes in line, escaped_count == rfc_count
      # (no escaping possible), skip the character-by-character walk entirely.
      unless line.include?('\\')
        return [rfc_count, rfc_count]
      end

      # escaped_count needs character-by-character walk for backslash tracking
      escaped_count = 0
      escaped = false

      line.each_char do |char|
        if char == quote_char
          escaped_count += 1 unless escaped
          escaped = false
        elsif char == '\\'
          escaped = !escaped
        else
          escaped = false
        end
      end

      [escaped_count, rfc_count]
    end

    private

    # Determine if a line has unbalanced quotes requiring multiline stitching.
    # For :auto mode, uses dual counting to avoid false multiline detection.
    # For :standard quote_boundary mode, uses a full state machine so that
    # mid-field quotes (which are literals in standard mode) do not trigger stitching.
    # Optimization #8: skip quote counting entirely when line has no quote chars.
    def detect_multiline(line, options)
      return false unless line.include?(options[:quote_char])

      if options[:quote_boundary] == :standard
        detect_multiline_strict(line, options)
      elsif options[:quote_escaping] == :auto
        escaped_count, rfc_count = count_quote_chars_auto(line, options[:quote_char], options[:col_sep])
        # If backslash-aware count is even → line is self-contained either way
        # If backslash-aware count is odd AND rfc_count is also odd → truly multiline
        # If backslash-aware count is odd AND rfc_count is even → NOT multiline
        #   (the RFC interpretation closes all fields on this line)
        escaped_count.odd? && rfc_count.odd?
      else
        count_quote_chars(line, options[:quote_char], options[:col_sep], options[:quote_escaping]).odd?
      end
    end

    # Boundary-aware multiline detection for quote_boundary: :standard mode.
    # Walks the line as a state machine tracking quote state only for boundary quotes.
    # A quote only opens/closes a quoted field if it appears at a field boundary
    # (start of field, or after leading whitespace when strip_whitespace is true).
    # Mid-field quotes are treated as literals and do not affect quote state.
    #
    # Optimization #17: single-char col_sep fast path uses byteindex skip-ahead
    # (mirrors Opt #10/#12 in parse_csv_line_ruby) so that:
    #   - inside a quoted field: jump directly to next quote char via C-level byteindex
    #   - inside an unquoted field: jump directly to next col_sep via C-level byteindex
    # This makes detect_multiline_strict competitive with parse_csv_line_ruby on the same
    # content, enabling it to serve as a cheap gate in the stitch loop (Opt #18).
    def detect_multiline_strict(line, options)
      col_sep = options[:col_sep]
      quote   = options[:quote_char]
      strip   = options[:strip_whitespace]
      row_sep = options[:row_sep]

      col_sep_size  = col_sep.size
      row_sep_size  = row_sep.is_a?(String) ? row_sep.size : 0
      in_quotes     = false
      field_started = false

      if col_sep_size == 1
        # Fast path: byte-level scanning with byteindex skip-ahead (Opt #17)
        col_sep_byte     = col_sep.getbyte(0)
        quote_byte       = quote.getbyte(0)
        row_sep_bytesize = row_sep.is_a?(String) ? row_sep.bytesize : 0
        bytesize         = line.bytesize
        byteindex_available = SmarterCSV::Parser::BYTEINDEX_AVAILABLE
        i = 0

        while i < bytesize
          if in_quotes
            # Opt #10 mirror: jump directly to next quote using C-level byteindex (MRI Ruby ≥ 3.2).
            # Fallback for older Ruby / JRuby: manual getbyte loop — kept inline to avoid
            # method-call frame overhead in this hot loop (see BYTEINDEX_AVAILABLE in parser.rb).
            next_q = if byteindex_available
                       line.byteindex(quote, i)
                     else
                       j = i
                       j += 1 while j < bytesize && line.getbyte(j) != quote_byte
                       j < bytesize ? j : nil
                     end
            return true if next_q.nil? # no closing quote → line is incomplete

            i = next_q
            b = quote_byte
          elsif field_started
            # Opt #12 mirror: unquoted field in progress — jump to next col_sep using C-level
            # byteindex (MRI Ruby ≥ 3.2). Fallback for older Ruby / JRuby: manual getbyte loop —
            # kept inline for the same reason as the Opt #10 mirror above.
            next_sep = if byteindex_available
                         line.byteindex(col_sep, i)
                       else
                         j = i
                         j += 1 while j < bytesize && line.getbyte(j) != col_sep_byte
                         j < bytesize ? j : nil
                       end
            break if next_sep.nil? # no more separators → end of line, not multiline

            i = next_sep
            b = col_sep_byte
          else
            b = line.getbyte(i)
          end

          if b == col_sep_byte && !in_quotes
            field_started = false
          elsif b == quote_byte
            if in_quotes
              # closing quote: only valid if followed by col_sep, row_sep, or end of line
              next_i = i + 1
              if next_i >= bytesize ||
                 line.getbyte(next_i) == col_sep_byte ||
                 (row_sep_bytesize > 0 && line.byteslice(next_i, row_sep_bytesize) == row_sep)
                in_quotes     = false
                field_started = true
              end
              # else: quote inside quoted field → literal (handles "" doubling)
            elsif !field_started # at field boundary: open quoted field
              in_quotes     = true
              field_started = true
            end
            # else: mid-field quote → literal, no state change
          else
            unless in_quotes
              # rubocop:disable Style/MultipleComparison -- two direct == comparisons are faster than Array#include? in this hot loop
              field_started = true unless strip && (b == 32 || b == 9) # ' ' == 32, '\t' == 9
              # rubocop:enable Style/MultipleComparison
            end
          end
          i += 1
        end
      else
        # Multi-char col_sep: character-by-character (original path)
        line_size = line.size
        i = 0

        while i < line_size
          # Check for column separator (only outside quotes)
          if !in_quotes && line[i...i + col_sep_size] == col_sep
            field_started = false
            i += col_sep_size
            next
          end

          if line[i] == quote
            if in_quotes
              # closing quote: only valid if followed by col_sep, row_sep, or end of line
              next_i = i + 1
              if next_i >= line_size ||
                 line[next_i...next_i + col_sep_size] == col_sep ||
                 (row_sep_size > 0 && line[next_i...next_i + row_sep_size] == row_sep)
                in_quotes     = false
                field_started = true
              end
              # else: quote inside quoted field → literal (handles "" doubling)
            elsif !field_started # at field boundary: open quoted field
              in_quotes     = true
              field_started = true
            end
            # else: mid-field quote → literal, no state change
          elsif !in_quotes
            # Non-quote character: track whether field has started
            if strip
              # rubocop:disable Style/MultipleComparison -- two direct == comparisons are faster than Array#include? in this hot loop
              field_started = true unless line[i] == ' ' || line[i] == '\t'
              # rubocop:enable Style/MultipleComparison
            else
              field_started = true
            end
          end
          i += 1
        end
      end

      in_quotes # true → line ends inside a quoted field → needs stitching
    end

    protected

    # SEE: https://github.com/rails/rails/blob/32015b6f369adc839c4f0955f2d9dce50c0b6123/activesupport/lib/active_support/core_ext/object/blank.rb#L121
    # and in the future we might also include UTF-8 space characters: https://www.compart.com/en/unicode/category/Zs
    BLANK_RE = /\A\s*\z/.freeze

    # Optimization #5: fast-path empty string and nil checks before regex
    def blank?(value)
      case value
      when String
        value.empty? || BLANK_RE.match?(value)
      when NilClass
        true
      when Array
        value.all? { |elem| blank?(elem) }
      when Hash
        value.values.all? { |elem| blank?(elem) } # Focus on values only
      else
        false
      end
    end

    private

    # Parses a CSV line into a hash, applying transformations and filtering.
    # Returns the finished hash, or nil if the row should be skipped.
    def process_line_to_hash(line, options)
      # --- SPLIT LINE & DATA TRANSFORMATIONS --------------------------------
      # we are now stripping whitespace inside the parse() methods
      # we create additional columns on-the-fly when we find more data fields than headers
      hash, data_size = parse_line_to_hash(line, @headers, options)

      # Unclosed quote at end of line: signal caller to stitch next physical line
      return :needs_more if data_size == -1

      # Handle extra columns (more data fields than headers)
      if data_size > @headers.size
        if options[:missing_headers] == :raise
          raise SmarterCSV::HeaderSizeMismatch, "extra columns detected on line #{@file_line_count}"
        end

        # Update headers array for subsequent rows
        while @headers.size < data_size
          @headers << "#{options[:missing_header_prefix]}#{@headers.size + 1}".to_sym
        end
      end

      # if all values were blank (hash is nil) we ignore this CSV line
      return nil if hash.nil?

      # Apply column selection (only_headers / except_headers)
      hash.select! { |k, _| @only_headers_set.include?(k) }   if @only_headers_set
      hash.reject! { |k, _| @except_headers_set.include?(k) } if @except_headers_set

      # --- HASH TRANSFORMATIONS / POST-FILTERS --------------------------------
      if @use_acceleration
        # C already handled: remove_empty_values, convert_values_to_numeric, remove_zero_values.
        # Remove nil/"" keys left by key_mapping or empty CSV headers.
        if @delete_nil_keys
          hash.delete(nil)
          hash.delete('')
        end
        hash.delete(:"") if @delete_empty_keys

        # Only these Ruby-only post-filters remain (user-provided Ruby objects):
        if (matcher = options[:nil_values_matching])
          if options[:remove_empty_values]
            hash.delete_if do |_k, v|
              str_val = v.is_a?(String) ? v : (v.is_a?(Numeric) ? v.to_s : nil)
              str_val && matcher.match?(str_val)
            end
          else
            hash.each_key do |k|
              v = hash[k]
              str_val = v.is_a?(String) ? v : (v.is_a?(Numeric) ? v.to_s : nil)
              hash[k] = nil if str_val && matcher.match?(str_val)
            end
          end
        end

        if options[:value_converters]
          options[:value_converters].each do |key, converter|
            hash[key] = converter.convert(hash[key]) if hash.key?(key)
          end
        end
      else
        # Ruby fallback: all transformations done in Ruby
        hash = hash_transformations(hash, options)
      end

      # --- HASH VALIDATIONS -------------------------------------------------
      # will go here, and be able to:
      #  - validate correct format of the values for fields
      #  - required fields to be non-empty
      #  - ...
      # -----------------------------------------------------------------------

      return nil if options[:remove_empty_hashes] && hash.empty?

      hash
    end

    def enforce_utf8_encoding(line, options)
      # return line unless options[:force_utf8] || options[:file_encoding] !~ /utf-8/i

      line.force_encoding('utf-8').encode('utf-8', invalid: :replace, undef: :replace, replace: options[:invalid_byte_sequence])
    end

    def handle_bad_row(error, line, start_csv_line, start_file_line, options)
      @errors[:bad_row_count] = (@errors[:bad_row_count] || 0) + 1

      error_record = {
        csv_line_number: start_csv_line,
        file_line_number: start_file_line,
        file_lines_consumed: @file_line_count - start_file_line + 1,
        error_class: error.class,
        error_message: error.message,
      }
      error_record[:raw_logical_line] = line if options[:collect_raw_lines]

      on_bad_row = options[:on_bad_row]
      case on_bad_row
      when :skip
        # counted above; nothing more to collect
      when :collect
        (@errors[:bad_rows] ||= []) << error_record
      else
        # callable
        on_bad_row.call(error_record)
      end

      if options[:bad_row_limit] && @errors[:bad_row_count] > options[:bad_row_limit]
        raise TooManyBadRows, "Bad row limit of #{options[:bad_row_limit]} exceeded (#{@errors[:bad_row_count]} bad rows encountered)"
      end
    end
  end
end
