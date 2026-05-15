# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'

# ----------------------------------------------------------------------------
# Part 1 of the parallel-processing refactor: the quote-aware slicer.
#
# `SmarterCSV.slice(input, slice_size:, **options)` performs ONE cheap pass over
# a seekable input:
#   - skips any comment/skip_lines preamble, parses & fully processes the header
#     line (transformations, key_mapping, ...)  -> the `headers` array
#   - runs auto-detection once  (col_sep / row_sep / quote_char / ...)
#   - scans the rest quote-aware, counting LOGICAL rows (a quoted field may
#     contain embedded row_sep, so one logical row can span several physical lines)
#   - every `slice_size` logical rows it emits a byte-range slice:
#
#       { row_offset: <0-based logical-row index of this slice's first row>,
#         input:      <the input, echoed back>,
#         headers:    <the fully-processed headers, e.g. [:id, :name, :email, ...]>,
#         from_byte:  <0-based byte offset where this slice's first DATA row starts>,
#         to_byte:    <0-based byte offset just past this slice's last DATA row (exclusive)>,
#         options:    <user's options + detected separators, with the header line
#                      pre-consumed (headers_in_file: false, user_provided_headers:
#                      headers) and :skip_lines removed; :chunk_size passes through> }
#
# A worker then does — the slice bytes are pure data rows, no header line:
#   bytes = File.open(d[:input], 'rb') { |f| f.seek(d[:from_byte]); f.read(d[:to_byte] - d[:from_byte]) }
#   SmarterCSV.process(StringIO.new(bytes.force_encoding(d[:options][:file_encoding])), **d[:options])
# and recovers global row numbers as  d[:row_offset] + local_index.
#
# Known v1 limitations (not exercised here): non-path (non-seekable) inputs;
# malformed input where the cheap multiline detector and the full parser could
# disagree on a row boundary; ragged-column fixtures via the fuzzer (the fuzzer
# generates consistent column counts).
# ----------------------------------------------------------------------------

RSpec.describe 'SmarterCSV.slice' do
  let(:fixture_path) { 'spec/fixtures' }
  let(:slice_keys) { SmarterCSV::Slicer::SLICE_KEYS }

  # Re-process a single slice exactly the way a worker would: seek to
  # the byte range, re-tag with the file encoding, hand it to SmarterCSV.process.
  def process_slice(slice)
    bytes = File.open(slice[:input], 'rb') do |f|
      f.seek(slice[:from_byte])
      f.read(slice[:to_byte] - slice[:from_byte])
    end
    bytes.force_encoding(slice[:options][:file_encoding] || 'UTF-8')
    SmarterCSV.process(StringIO.new(bytes), **slice[:options])
  end

  # ==========================================================================
  # The original contract specs (kept verbatim, renamed to slice vocabulary).
  # ==========================================================================

  context 'with a small plain CSV (pets.csv: header + 4 data rows)' do
    let(:path) { "#{fixture_path}/pets.csv" }

    it 'returns an Array of slice Hashes with the expected keys' do
      slices = SmarterCSV.slice(path, slice_size: 2)

      expect(slices).to be_an(Array)
      expect(slices).to all(be_a(Hash))
      slices.each { |d| expect(d.keys).to match_array(slice_keys) }
    end

    it 'splits 4 rows into 2 slices of 2 when slice_size: 2' do
      slices = SmarterCSV.slice(path, slice_size: 2)

      expect(slices.size).to eq(2)
      expect(slices.map { |d| d[:row_offset] }).to eq([0, 2])
    end

    it 'puts all 4 rows in a single slice when slice_size >= row count' do
      slices = SmarterCSV.slice(path, slice_size: 100)

      expect(slices.size).to eq(1)
      expect(slices.first[:row_offset]).to eq(0)
    end

    it 'echoes the input path back unchanged' do
      slices = SmarterCSV.slice(path, slice_size: 2)
      expect(slices).to all(include(input: path))
    end

    it 'carries the fully-processed headers array (symbols, under default settings)' do
      slices = SmarterCSV.slice(path, slice_size: 2)
      expect(slices).to all(include(headers: %i[first_name last_name dogs cats birds fish]))
      # the worker options say "headers already processed, do not re-parse a header line"
      slices.each do |d|
        expect(d[:options][:headers_in_file]).to eq(false)
        expect(d[:options][:user_provided_headers]).to eq(%i[first_name last_name dogs cats birds fish])
      end
    end

    it 'carries the detected separators in :options' do
      slices = SmarterCSV.slice(path, slice_size: 2)
      opts = slices.first[:options]
      expect(opts[:col_sep]).to eq(',')
      expect(opts[:row_sep]).to eq("\n")
      expect(opts[:quote_char]).to eq('"')
    end

    it 'produces byte ranges that are contiguous, non-overlapping, and cover from end-of-header to EOF' do
      slices = SmarterCSV.slice(path, slice_size: 2)
      file_size   = File.size(path)
      header_size = "first name,last name,dogs,cats,birds,fish\n".bytesize

      expect(slices.first[:from_byte]).to eq(header_size)
      expect(slices.last[:to_byte]).to eq(file_size)
      slices.each_cons(2) { |a, b| expect(b[:from_byte]).to eq(a[:to_byte]) }
      slices.each { |d| expect(d[:from_byte]).to be < d[:to_byte] }
    end

    # The contract that actually matters: reconstructing each slice and processing
    # it reproduces exactly the corresponding slice of the whole-file result.
    it 'each slice re-processes to the matching slice of the whole-file result' do
      whole       = SmarterCSV.process(path)
      slices = SmarterCSV.slice(path, slice_size: 2)

      slices.each do |d|
        expect(process_slice(d)).to eq(whole[d[:row_offset], 2])
      end
    end

    it 'concatenating all slices reproduces the whole-file result, with global row numbers from row_offset' do
      whole = SmarterCSV.process(path)
      slices = SmarterCSV.slice(path, slice_size: 2)

      reassembled = []
      slices.each do |d|
        process_slice(d).each_with_index { |hash, i| reassembled[d[:row_offset] + i] = hash }
      end
      expect(reassembled).to eq(whole)
    end

    it 'passes user-supplied :chunk_size through to worker options (orthogonal to :slice_size)' do
      slices = SmarterCSV.slice(path, slice_size: 2, chunk_size: 7)

      slices.each do |d|
        expect(d[:options][:chunk_size]).to eq(7)
      end
    end
  end

  context 'with logical rows that span several physical lines (continuation_lines.csv)' do
    let(:path) { "#{fixture_path}/continuation_lines.csv" }

    it 'never splits a row in the middle of a quoted, embedded-newline field' do
      whole = SmarterCSV.process(path)
      slices = SmarterCSV.slice(path, slice_size: 1)

      # one slice per logical row, in order
      expect(slices.map { |d| d[:row_offset] }).to eq((0...whole.size).to_a)
      slices.each { |d| expect(process_slice(d)).to eq([whole[d[:row_offset]]]) }
    end
  end

  context 'with CRLF line endings (carriage_returns_rn.csv)' do
    let(:path) { "#{fixture_path}/carriage_returns_rn.csv" }

    it 'detects row_sep and slices on CRLF logical-row boundaries' do
      whole       = SmarterCSV.process(path)
      slices = SmarterCSV.slice(path, slice_size: 2)

      expect(slices.first[:options][:row_sep]).to eq("\r\n")
      reassembled = []
      slices.each do |d|
        process_slice(d).each_with_index { |hash, i| reassembled[d[:row_offset] + i] = hash }
      end
      expect(reassembled).to eq(whole)
    end
  end

  context 'edge cases' do
    it 'raises EmptyFileError for an empty (zero-byte) file (mirrors SmarterCSV.process)' do
      Tempfile.create(['empty', '.csv']) do |f|
        f.flush
        expect { SmarterCSV.slice(f.path, slice_size: 10) }.to raise_error(SmarterCSV::EmptyFileError)
      end
    end

    it 'returns [] for a header-only file (no data rows)' do
      Tempfile.create(['header_only', '.csv']) do |f|
        f.write("a,b,c\n")
        f.flush
        expect(SmarterCSV.slice(f.path, slice_size: 10)).to eq([])
      end
    end

    it 'raises ArgumentError when slice_size is not a positive Integer' do
      expect { SmarterCSV.slice("#{fixture_path}/pets.csv", slice_size: 0) }.to raise_error(ArgumentError)
      expect { SmarterCSV.slice("#{fixture_path}/pets.csv", slice_size: -1) }.to raise_error(ArgumentError)
    end

    it 'raises ArgumentError for a non-path (non-seekable) input — not supported yet' do
      io = StringIO.new("a,b\n1,2\n")
      expect { SmarterCSV.slice(io, slice_size: 10) }.to raise_error(ArgumentError, /file path/)
    end
  end

  # ==========================================================================
  # Hardening additions: broad round-trip fidelity matrix + a fuzzer.
  # These are EXTRA coverage on top of the contract specs above.
  # ==========================================================================

  # Assertions that must hold for any (file, options, slice_size) where the file
  # has at least one data row. `expected_headers` is optional (skipped if nil).
  def expect_well_formed_slice(path, slices, slice_size, expected_headers: nil)
    expect(slices).not_to be_empty
    expect(slices).to all(be_a(Hash))
    slices.each { |d| expect(d.keys).to match_array(slice_keys) }

    # row_offset runs 0, slice_size, 2*slice_size, ...
    expect(slices.map { |d| d[:row_offset] }).to eq((0...slices.size).map { |i| i * slice_size })

    # input echoed back; headers identical across all slices (and == expected, if given)
    expect(slices).to all(include(input: path))
    header_sets = slices.map { |d| d[:headers] }.uniq
    expect(header_sets.size).to eq(1)
    expect(expected_headers).to eq(header_sets.first) unless expected_headers.nil?
    # worker options say "headers already processed"; byte ranges are non-empty
    slices.each do |d|
      expect(d[:options][:headers_in_file]).to eq(false)
      expect(d[:options][:user_provided_headers]).to eq(d[:headers])
      expect(d[:options]).not_to include(:skip_lines)
      expect(d[:from_byte]).to be < d[:to_byte]
    end

    # byte ranges: contiguous, last reaches EOF
    slices.each_cons(2) { |a, b| expect(b[:from_byte]).to eq(a[:to_byte]) }
    expect(slices.last[:to_byte]).to eq(File.size(path))
  end

  describe 'round-trip fidelity across fixtures' do
    # [ relative fixture path, options to pass to both process and slice ]
    [
      ['pets.csv',                    {}],
      ['basic.csv',                   {}],                                  # non-ASCII data (Hernán, Curaçon)
      ['quoted.csv',                  {}],                                  # doubled "" quotes, embedded comma
      ['quoted2.csv',                 {}],                                  # quoted headers with ""
      ['continuation_lines.csv',      {}],                                  # embedded \n inside a quoted field
      ['carriage_returns_rn.csv',     {}],                                  # CRLF, auto-detected
      ['carriage_returns_quoted.csv', {}],                                  # embedded \r inside a quoted field
      ['bom_test_efbbbf.csv',         { col_sep: ',', row_sep: "\r\n" }],   # UTF-8 BOM + CRLF, explicit
      ['bom_test_efbbbf.csv',         { col_sep: :auto, row_sep: :auto }],  # UTF-8 BOM + auto-detect
      ['escaped_quote_char.csv',      { quote_escaping: :backslash }],      # backslash-escaped quotes
      ['ignore_comments.csv',         {}],                                  # comment lines treated as data
      ['ignore_comments.csv',         { comment_regexp: /\A#/ }],           # comment lines (incl. before 1st data row) skipped
      ['key_mapping.csv',             { key_mapping: { this: :renamed_this } }],
      ['line_endings_r.csv',          { row_sep: "\r" }],                   # \r-only row separator, explicit
    ].each do |rel_path, options|
      [1, 2, 3, 1000].each do |slice_size|
        it "#{rel_path} #{options.inspect}  slice_size=#{slice_size}: slices re-process to the whole-file result" do
          path  = "#{fixture_path}/#{rel_path}"
          whole = SmarterCSV.process(path, **options)
          reader_headers = SmarterCSV::Reader.new(path, options).tap(&:process).headers

          slices = SmarterCSV.slice(path, slice_size: slice_size, **options)

          expect_well_formed_slice(path, slices, slice_size, expected_headers: reader_headers)
          # the core invariant — process each slice, concatenate in slice order, == whole
          expect(slices.flat_map { |d| process_slice(d) }).to eq(whole)
        end
      end
    end
  end

  describe 'fuzz: random CSVs round-trip through slice + per-slice process' do
    # Deterministic — bump the seed if you want a different sample.
    SEED = 0xC0FFEE

    def random_field(rng)
      case rng.rand(8)
      when 0 then ''
      when 1 then rng.rand(1_000_000).to_s
      when 2 then "word#{rng.rand(10_000)}"
      when 3 then "has,comma#{rng.rand(1000)}"
      when 4 then "has\nnewline#{rng.rand(1000)}"
      when 5 then %(has"quote#{rng.rand(1000)})
      when 6 then "comma,and\nnewline#{rng.rand(1000)}"
      else        "spaced #{rng.rand(1000)} value"
      end
    end

    def csv_escape(field)
      if field.match?(/[",\r\n]/)
        %("#{field.gsub('"', '""')}")
      else
        field
      end
    end

    def random_csv(rng)
      ncols = 2 + rng.rand(5)        # 2..6 columns (consistent across all rows)
      nrows = rng.rand(25)           # 0..24 data rows
      header = (1..ncols).map { |i| "col_#{i}" }
      lines  = [header] + Array.new(nrows) { Array.new(ncols) { random_field(rng) } }
      [lines.map { |row| row.map { |f| csv_escape(f) }.join(',') }.join("\n") + "\n", nrows]
    end

    it 'reassembles to SmarterCSV.process for many random files and slice sizes' do
      rng = Random.new(SEED)

      40.times do |iter|
        csv_text, nrows = random_csv(rng)
        Tempfile.create(["fuzz_#{iter}", '.csv']) do |f|
          f.binmode
          f.write(csv_text)
          f.flush

          whole = SmarterCSV.process(f.path)

          [1, 2, 3, 5, 17, 1000].each do |slice_size|
            slices = SmarterCSV.slice(f.path, slice_size: slice_size)

            if nrows.zero?
              expect(slices).to eq([]), "iter=#{iter} slice_size=#{slice_size}: expected no slices for a header-only file"
              next
            end

            expect(slices.size).to eq((nrows.to_f / slice_size).ceil),
                                   "iter=#{iter} slice_size=#{slice_size}\n#{csv_text.inspect}"
            expect_well_formed_slice(f.path, slices, slice_size)
            expect(slices.flat_map { |d| process_slice(d) }).to eq(whole),
                                                                "iter=#{iter} slice_size=#{slice_size}\n#{csv_text.inspect}"
          end
        end
      end
    end
  end
end
