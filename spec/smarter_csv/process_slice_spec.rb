# frozen_string_literal: true

require 'spec_helper'

# Tests for Reader#process_slice — Step 2a of the parallel slice-mode design.
# These exercise the worker-side entry point: takes a slice produced by
# SmarterCSV.slice, reads the slice's byte range from the input file, and
# parses rows via the shared process_rows core (extracted in Step 1).
#
# The parity contract: for every (file, options, slice_size) combo, the
# concatenation of per-slice process_slice results MUST equal SmarterCSV.process
# on the whole file. This is the same invariant slicer_spec asserts via an
# inline seek+read recipe; once SmarterCSV.process_slice (the module-level
# wrapper, Step 2b) lands, slicer_spec will delegate through it.

RSpec.describe 'SmarterCSV::Reader#process_slice' do
  let(:fixture_path) { 'spec/fixtures' }

  # Worker entry point shorthand: create a fresh Reader and process one slice.
  # Mirrors what SmarterCSV.process_slice will do in Step 2b.
  def parse_slice(slice, &block)
    SmarterCSV::Reader.new(slice[:input], slice[:options]).process_slice(slice, &block)
  end

  context 'happy path on pets.csv (header + 4 data rows)' do
    let(:path) { "#{fixture_path}/pets.csv" }

    it 'a single slice covering the whole file parses identically to SmarterCSV.process' do
      whole  = SmarterCSV.process(path)
      slices = SmarterCSV.slice(path, slice_size: 1000)

      expect(slices.size).to eq(1)
      expect(parse_slice(slices.first)).to eq(whole)
    end

    it 'concatenated multi-slice results match SmarterCSV.process on the whole file' do
      whole  = SmarterCSV.process(path)
      slices = SmarterCSV.slice(path, slice_size: 2)

      expect(slices.flat_map { |s| parse_slice(s) }).to eq(whole)
    end

    it 'yields row-by-row (as [hash] arrays) when called with a block and no chunk_size' do
      slices  = SmarterCSV.slice(path, slice_size: 1000)
      yielded = []
      parse_slice(slices.first) { |batch, _i| yielded << batch }

      expect(yielded.map(&:size)).to eq([1, 1, 1, 1])
      expect(yielded.flatten).to eq(SmarterCSV.process(path))
    end

    it 'yields batches of chunk_size when chunk_size is set in slice options' do
      slices  = SmarterCSV.slice(path, slice_size: 1000, chunk_size: 2)
      yielded = []
      # process_rows reuses the chunk Array (clears after each yield) — callers
      # that need to keep the batch past the yield must dup, same contract as
      # Reader#each_chunk.
      parse_slice(slices.first) { |batch, _i| yielded << batch.dup }

      expect(yielded.size).to eq(2) # 4 rows / chunk_size 2 = 2 batches
      expect(yielded.map(&:size)).to eq([2, 2])
      expect(yielded.flatten).to eq(SmarterCSV.process(path))
    end

    it 'returns an Array of row hashes when called without a block' do
      slices = SmarterCSV.slice(path, slice_size: 1000)
      result = parse_slice(slices.first)

      expect(result).to be_an(Array)
      expect(result).to eq(SmarterCSV.process(path))
    end
  end

  describe 'reader state after process_slice' do
    let(:path) { "#{fixture_path}/pets.csv" }

    it 'reader.headers reflects what this slice contained (canonical headers from the slice)' do
      slice  = SmarterCSV.slice(path, slice_size: 1000).first
      reader = SmarterCSV::Reader.new(slice[:input], slice[:options])
      reader.process_slice(slice)

      expect(reader.headers).to eq(%i[first_name last_name dogs cats birds fish])
    end

    it 'on a reused Reader, line counters reset per slice (within-slice positions, not cumulative)' do
      slices = SmarterCSV.slice(path, slice_size: 2) # 2 slices of 2 rows each
      reader = SmarterCSV::Reader.new(slices.first[:input], slices.first[:options])

      reader.process_slice(slices[0])
      after_first_csv  = reader.csv_line_count
      after_first_file = reader.file_line_count

      reader.process_slice(slices[1])

      # Second call's counters equal first call's — not 2 × first
      expect(reader.csv_line_count).to eq(after_first_csv)
      expect(reader.file_line_count).to eq(after_first_file)
    end

    it 'on a reused Reader (no block), @result accumulates rows across slice calls' do
      whole  = SmarterCSV.process(path)
      slices = SmarterCSV.slice(path, slice_size: 2)
      reader = SmarterCSV::Reader.new(slices.first[:input], slices.first[:options])

      slices.each { |s| reader.process_slice(s) }

      expect(reader.result).to eq(whole)
    end
  end

  describe 'edge cases' do
    it 'raises ArgumentError when the slice argument is not a Hash' do
      reader = SmarterCSV::Reader.new("#{fixture_path}/pets.csv", {})

      expect { reader.process_slice("not a hash") }.to raise_error(ArgumentError, /must be a Hash/)
    end

    it 'raises ArgumentError when the slice Hash is missing required keys' do
      reader  = SmarterCSV::Reader.new("#{fixture_path}/pets.csv", {})
      partial = { from_byte: 0, to_byte: 10, input: "any" } # missing row_offset, headers, options

      expect { reader.process_slice(partial) }.to raise_error(ArgumentError, /missing keys/)
    end

    it 'raises Errno::ENOENT when slice[:input] does not exist' do
      slice     = SmarterCSV.slice("#{fixture_path}/pets.csv", slice_size: 1000).first
      bad_slice = slice.merge(input: '/nonexistent/path.csv')
      reader    = SmarterCSV::Reader.new(bad_slice[:input], bad_slice[:options])

      expect { reader.process_slice(bad_slice) }.to raise_error(Errno::ENOENT)
    end
  end

  describe 'round-trip parity across fixtures' do
    # Same parity contract as slicer_spec's matrix, but exercising process_slice
    # rather than the inline seek+read recipe. Subset of fixtures (the full
    # matrix lives in slicer_spec.rb and will continue to exercise process_slice
    # transitively once slicer_spec's helper is rewritten in Step 2e).
    [
      ['pets.csv',                    {}],
      ['basic.csv',                   {}],
      ['quoted.csv',                  {}],
      ['continuation_lines.csv',      {}],
      ['carriage_returns_rn.csv',     {}],
      ['carriage_returns_quoted.csv', {}],
      ['ignore_comments.csv',         { comment_regexp: /\A#/ }],
      ['escaped_quote_char.csv',      { quote_escaping: :backslash }],
      ['key_mapping.csv',             { key_mapping: { this: :renamed_this } }],
    ].each do |rel_path, options|
      [1, 2, 1000].each do |slice_size|
        it "#{rel_path} #{options.inspect}  slice_size=#{slice_size}: per-slice == whole-file" do
          path     = "#{fixture_path}/#{rel_path}"
          whole    = SmarterCSV.process(path, **options)
          slices   = SmarterCSV.slice(path, slice_size: slice_size, **options)
          combined = slices.flat_map { |s| parse_slice(s) }

          expect(combined).to eq(whole)
        end
      end
    end
  end

  describe 'acceleration on/off transparency' do
    let(:path) { "#{fixture_path}/pets.csv" }

    [true, false].each do |accel|
      it "produces identical rows with acceleration: #{accel}" do
        whole  = SmarterCSV.process(path, acceleration: accel)
        slices = SmarterCSV.slice(path, slice_size: 2, acceleration: accel)

        expect(slices.flat_map { |s| parse_slice(s) }).to eq(whole)
      end
    end
  end
end
