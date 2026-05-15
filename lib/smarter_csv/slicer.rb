# frozen_string_literal: true

module SmarterCSV
  # Part 1 of the parallel-processing design: the quote-aware slicer.
  #
  # Performs ONE pass over a seekable input (a file path), reusing the Reader's
  # auto-detection + header machinery, then scans the rest quote-aware to find
  # LOGICAL-row boundaries and emits byte-range slices that parallel workers
  # can seek into independently. See docs / parallel_processing_csv_files.md.
  #
  # Header processing (parsing the header line, transforming it, applying
  # key_mapping, etc.) happens HERE, once. Each slice carries the
  # fully-processed `headers` array — with default settings, an array of symbols
  # like [:id, :name, :email, ...] — so workers consume it as-is and never
  # re-parse a header line.
  #
  # Each slice:
  #   { row_offset: <0-based logical-row index of this slice's first row>,
  #     input:      <the file path, echoed back>,
  #     headers:    <the fully-processed headers, e.g. [:id, :name, :email, ...]>,
  #     from_byte:  <0-based byte offset where this slice's first data row starts>,
  #     to_byte:    <0-based byte offset just past this slice's last data row (exclusive)>,
  #     options:    <user's options + detected separators, with the header line
  #                  pre-consumed (headers_in_file: false, user_provided_headers:
  #                  headers) and :skip_lines removed> }
  #
  # Two distinct row-count knobs live in their own namespaces:
  #
  #   - :slice_size  — how many logical rows go into ONE worker slice
  #                    (the slicer's argument; typical values 10k–100k)
  #   - :chunk_size  — within a worker, how many rows the block yields at once
  #                    (the Reader's existing option; typical values 100–1000).
  #                    Passed through to workers untouched.
  #
  # A worker then does — note the slice bytes are pure data rows, no header line:
  #   bytes = File.open(d[:input], 'rb') { |f| f.seek(d[:from_byte]); f.read(d[:to_byte] - d[:from_byte]) }
  #   bytes.force_encoding(d[:options][:file_encoding])
  #   SmarterCSV.process(StringIO.new(bytes), **d[:options]) { |row| ... }
  # and recovers global row numbers as  d[:row_offset] + local_index.
  #
  # NOTE: v1 leans on SmarterCSV::Reader for option resolution, auto-detection,
  # and header parsing rather than being fully self-contained — consolidating
  # that into one extracted piece is a planned follow-up.
  class Slicer
    SLICE_KEYS = %i[row_offset input headers from_byte to_byte options].freeze

    def initialize(input, given_options = {})
      unless input.is_a?(String)
        raise ArgumentError,
              "SmarterCSV.slice requires a file path (got #{input.class}); " \
              "non-seekable inputs are not supported yet"
      end

      @input         = input
      @given_options = given_options.dup
      # Reader.new only resolves options — it does not touch the file — so this
      # is side-effect-free. We drive its detection/header methods below.
      @reader = SmarterCSV::Reader.new(input, given_options)
    end

    # Returns an Array of slice Hashes (see SLICE_KEYS), one per slice
    # of up to `slice_size` logical data rows. Empty when the file has a header
    # but no data rows. Raises SmarterCSV::EmptyFileError on a truly empty /
    # blank-header file (mirroring SmarterCSV.process).
    def slice(slice_size:)
      unless slice_size.is_a?(Integer) && slice_size >= 1
        raise ArgumentError, "slice_size must be an Integer >= 1 (got #{slice_size.inspect})"
      end

      r       = @reader
      options = r.options

      # Binary mode (no newline translation; byte-accurate #pos/#bytesize) but
      # tagged with the file encoding so the parsed header line — and therefore
      # the `headers` array — matches what SmarterCSV.process(path) produces.
      fh = File.open(@input, "rb:#{options[:file_encoding]}")
      begin
        detect_separators!(r, fh, options)

        # Skip preamble + parse & fully process the header line — reuses all of
        # Reader's header handling (BOM, comments, transformations, key_mapping,
        # EmptyFileError, ...). `headers` is the final array workers consume.
        r.send(:skip_lines, fh, options) if options[:skip_lines]
        headers, _size  = r.send(:process_headers, fh, options)
        data_start_byte = fh.pos # bytes consumed so far = preamble + on-disk header line

        rows = scan_logical_rows(r, fh, options, data_start_byte) # [[start_byte, end_byte_excl], ...]
        return [] if rows.empty?

        file_size = fh.pos # the scan read to EOF

        # Contiguous tiling over [data_start_byte, EOF): each logical row's span
        # runs from its own start to the *next* row's start (so any comment lines
        # between data rows fold into the preceding row's slice and get re-skipped
        # by `process` at worker time); the first row's span starts at
        # data_start_byte; the last row's span ends at EOF.
        spans = rows.each_index.map do |i|
          start_b = i.zero? ? data_start_byte : rows[i][0]
          end_b   = i + 1 < rows.size ? rows[i + 1][0] : file_size
          [start_b, end_b]
        end

        worker_options = build_worker_options(options, headers)

        spans.each_slice(slice_size).each_with_index.map do |slice_spans, idx|
          {
            row_offset: idx * slice_size,
            input: @input,
            headers: headers,
            from_byte: slice_spans.first.first,
            to_byte: slice_spans.last.last,
            options: worker_options,
          }
        end
      ensure
        fh.close
      end
    end

    private

    # Mirrors the auto-detection block in Reader#process. A file path is always
    # seekable, so we use native rewind (no PeekableIO).
    def detect_separators!(reader, fh, options)
      return unless options[:row_sep]&.to_sym == :auto || options[:col_sep]&.to_sym == :auto

      reset_line_counts!(reader)
      options[:row_sep] = reader.send(:guess_line_ending, fh, options) if options[:row_sep]&.to_sym == :auto
      fh.rewind
      reset_line_counts!(reader)
      reader.send(:skip_lines, fh, options) if options[:skip_lines] && options[:col_sep]&.to_sym == :auto
      options[:col_sep] = reader.send(:guess_column_separator, fh, options) if options[:col_sep]&.to_sym == :auto
      fh.rewind
      reset_line_counts!(reader)
    end

    # Walks physical lines from data_start_byte to EOF, stitching any line that
    # ends inside a quoted field onto the next (so a logical row with embedded
    # row_sep stays whole), and skipping comment lines. Returns one
    # [start_byte, end_byte_exclusive] pair per logical data row.
    def scan_logical_rows(reader, fh, options, data_start_byte)
      row_sep    = options[:row_sep]
      comment_re = options[:comment_regexp]
      fh.seek(data_start_byte)

      rows        = []
      run_start   = nil # start byte of a logical row currently being stitched
      accumulated = nil
      byte        = data_start_byte

      loop do
        line_start = byte
        line = fh.gets(row_sep)
        break if line.nil?

        byte += line.bytesize

        # Comment line (and not in the middle of a multiline row): not a data row.
        # Its bytes fold into whichever slice span contains them.
        next if comment_re && run_start.nil? && line =~ comment_re

        if run_start.nil?
          run_start   = line_start
          accumulated = line.dup
        else
          accumulated << line
        end

        next if reader.send(:detect_multiline, accumulated, options) # still inside a quoted field

        rows << [run_start, byte]
        run_start = nil
      end

      # Unclosed quoted field at EOF: record what we have. `process` will raise
      # MalformedCSV on this slice — same as it does on the whole file today.
      rows << [run_start, byte] unless run_start.nil?
      rows
    end

    def reset_line_counts!(reader)
      reader.instance_variable_set(:@file_line_count, 0)
      reader.instance_variable_set(:@csv_line_count, 0)
    end

    # The options a worker passes to SmarterCSV.process on its slice. We build
    # from the user's original options (not the fully-resolved hash — that one
    # carries every default key, including deprecated ones, which would trigger
    # spurious deprecation warnings on the worker side), then:
    #   - override the auto-detected separators (workers never re-detect)
    #   - feed the already-processed headers as user_provided_headers, with
    #     headers_in_file: false (the slice bytes are pure data rows)
    #   - drop skip_lines (the preamble is already gone)
    #
    # :chunk_size (Reader's batch-yield knob — orthogonal to :slice_size) is
    # NOT stripped: it's how the user wants the worker's block to yield, and
    # passing it through is what they almost certainly want for insert_all /
    # push_bulk patterns.
    def build_worker_options(options, headers)
      @given_options
        .merge(
          col_sep: options[:col_sep],
          row_sep: options[:row_sep],
          quote_char: options[:quote_char],
          quote_escaping: options[:quote_escaping],
          quote_boundary: options[:quote_boundary],
          file_encoding: options[:file_encoding],
          headers_in_file: false,
          user_provided_headers: headers
        )
        .tap { |o| o.delete(:skip_lines) }
    end
  end
end
