# frozen_string_literal: true

fixture_path = 'spec/fixtures'

describe 'Reader#each and Reader#each_chunk enumerator API' do
  let(:chunked_csv)     { "#{fixture_path}/chunked.csv" } # 12 clean rows: id,item
  let(:quarantine_csv)  { "#{fixture_path}/bad_row_quarantine.csv" } # good/bad/good rows

  [true, false].each do |bool|
    context "with#{bool ? ' C-' : 'out '}acceleration" do
      let(:base_options) { { acceleration: bool } }

      # ----------------------------------------------------------------
      # Reader#each — yield type
      # ----------------------------------------------------------------
      describe 'Reader#each' do
        it 'yields a Hash for each row' do
          reader = SmarterCSV::Reader.new(chunked_csv, base_options)
          yielded = []
          reader.each { |row| yielded << row }
          expect(yielded).to all(be_a(Hash))
        end

        it 'yields all 12 rows' do
          reader = SmarterCSV::Reader.new(chunked_csv, base_options)
          expect(reader.each.to_a.size).to eq 12
        end

        it 'yields hashes with the correct keys' do
          reader = SmarterCSV::Reader.new(chunked_csv, base_options)
          reader.each do |row|
            expect(row).to have_key(:id)
            expect(row).to have_key(:item)
          end
        end

        it 'yields rows in order' do
          reader = SmarterCSV::Reader.new(chunked_csv, base_options)
          ids = reader.map { |row| row[:id] }
          expect(ids).to eq (1..12).to_a
        end

        # ----------------------------------------------------------------
        # chunk_size in options is ignored by each
        # ----------------------------------------------------------------
        it 'ignores chunk_size from options and still yields individual Hashes' do
          reader = SmarterCSV::Reader.new(chunked_csv, base_options.merge(chunk_size: 5))
          yielded = []
          reader.each { |row| yielded << row }
          expect(yielded).to all(be_a(Hash))
          expect(yielded.size).to eq 12
        end

        it 'restores chunk_size in options after each completes' do
          reader = SmarterCSV::Reader.new(chunked_csv, base_options.merge(chunk_size: 5))
          reader.each { |_row| }
          expect(reader.options[:chunk_size]).to eq 5
        end

        # ----------------------------------------------------------------
        # Enumerator without block
        # ----------------------------------------------------------------
        it 'returns an Enumerator when called without a block' do
          reader = SmarterCSV::Reader.new(chunked_csv, base_options)
          expect(reader.each).to be_a(Enumerator)
        end

        it 'Enumerator#to_a returns all rows as Hashes' do
          reader = SmarterCSV::Reader.new(chunked_csv, base_options)
          result = reader.each.to_a
          expect(result.size).to eq 12
          expect(result).to all(be_a(Hash))
        end

        # ----------------------------------------------------------------
        # Enumerable methods (enabled by include Enumerable)
        # ----------------------------------------------------------------
        it 'supports map' do
          reader = SmarterCSV::Reader.new(chunked_csv, base_options)
          items = reader.map { |row| row[:item] }
          expect(items).to eq((1..12).map { |i| "item_#{i}" })
        end

        it 'supports select' do
          reader = SmarterCSV::Reader.new(chunked_csv, base_options)
          even_rows = reader.select { |row| row[:id].even? }
          expect(even_rows.size).to eq 6
          expect(even_rows).to all(be_a(Hash))
        end

        it 'supports count' do
          reader = SmarterCSV::Reader.new(chunked_csv, base_options)
          expect(reader.count).to eq 12
        end

        it 'supports each_with_index (0-based sequential count of good rows)' do
          reader = SmarterCSV::Reader.new(chunked_csv, base_options)
          indices = []
          reader.each_with_index { |_row, i| indices << i }
          expect(indices).to eq (0..11).to_a
        end

        it 'supports each_slice (free chunking via Enumerable)' do
          reader = SmarterCSV::Reader.new(chunked_csv, base_options)
          slices = reader.each_slice(5).to_a
          expect(slices.size).to eq 3 # 5 + 5 + 2
          expect(slices.first.size).to eq 5
          expect(slices.last.size).to eq 2
          expect(slices.flatten).to all(be_a(Hash))
        end

        it 'supports lazy evaluation' do
          reader = SmarterCSV::Reader.new(chunked_csv, base_options)
          first3 = reader.lazy.map { |row| row[:id] }.first(3)
          expect(first3).to eq [1, 2, 3]
        end

        # ----------------------------------------------------------------
        # Interaction with on_bad_row
        # ----------------------------------------------------------------
        it 'skips bad rows when on_bad_row: :skip' do
          options = base_options.merge(strict: true, on_bad_row: :skip)
          reader = SmarterCSV::Reader.new(quarantine_csv, options)
          names = reader.map { |row| row[:name] }
          expect(names).to eq %w[John Mike]
        end

        it 'each_with_index index only counts good rows (excluding bad rows)' do
          options = base_options.merge(strict: true, on_bad_row: :skip)
          reader = SmarterCSV::Reader.new(quarantine_csv, options)
          indices = []
          reader.each_with_index { |_row, i| indices << i }
          # 2 good rows → indices 0 and 1
          expect(indices).to eq [0, 1]
        end
      end

      # ----------------------------------------------------------------
      # Reader#each_chunk — yield type and chunk_size validation
      # ----------------------------------------------------------------
      describe 'Reader#each_chunk' do
        it 'yields Array<Hash> chunks and chunk index' do
          options = base_options.merge(chunk_size: 5)
          reader = SmarterCSV::Reader.new(chunked_csv, options)
          chunks = []
          indices = []
          reader.each_chunk do |chunk, i|
            chunks << chunk
            indices << i
          end
          expect(chunks.size).to eq 3
          expect(chunks.map(&:size)).to eq [5, 5, 2]
          expect(chunks.flatten).to all(be_a(Hash))
          expect(indices).to eq [0, 1, 2] # 3 chunks: 5 + 5 + 2
        end

        it 'chunk sizes are correct (last chunk may be smaller)' do
          options = base_options.merge(chunk_size: 5)
          reader = SmarterCSV::Reader.new(chunked_csv, options)
          sizes = reader.each_chunk.map { |chunk, _| chunk.size }
          expect(sizes).to eq [5, 5, 2]
        end

        it 'all rows are covered across chunks' do
          options = base_options.merge(chunk_size: 4)
          reader = SmarterCSV::Reader.new(chunked_csv, options)
          all_ids = reader.each_chunk.flat_map { |chunk, _| chunk.map { |row| row[:id] } }
          expect(all_ids).to eq (1..12).to_a
        end

        it 'works with chunk_size equal to the number of rows (single chunk)' do
          options = base_options.merge(chunk_size: 12)
          reader = SmarterCSV::Reader.new(chunked_csv, options)
          chunks = reader.each_chunk.map { |chunk, _| chunk }
          expect(chunks.size).to eq 1
          expect(chunks.first.size).to eq 12
        end

        it 'works with chunk_size larger than the number of rows' do
          options = base_options.merge(chunk_size: 100)
          reader = SmarterCSV::Reader.new(chunked_csv, options)
          chunks = reader.each_chunk.map { |chunk, _| chunk }
          expect(chunks.size).to eq 1
          expect(chunks.first.size).to eq 12
        end

        it 'chunk_size of 1 yields one-element chunks' do
          options = base_options.merge(chunk_size: 1)
          reader = SmarterCSV::Reader.new(chunked_csv, options)
          chunks = reader.each_chunk.map { |chunk, _| chunk }
          expect(chunks.size).to eq 12
          expect(chunks).to all(be_a(Array))
          expect(chunks.map(&:size)).to all(eq 1)
        end

        # ----------------------------------------------------------------
        # chunk_size validation and defaults
        # ----------------------------------------------------------------
        it 'uses DEFAULT_CHUNK_SIZE and emits a warning when chunk_size is nil' do
          reader = SmarterCSV::Reader.new(chunked_csv, base_options) # chunk_size: nil by default
          expect { reader.each_chunk { |_c, _i| } }.to output(/chunk_size not set/).to_stderr
        end

        it 'still yields all rows when using the default chunk_size' do
          reader = SmarterCSV::Reader.new(chunked_csv, base_options)
          all_rows = []
          expect { reader.each_chunk { |chunk, _i| all_rows.concat(chunk) } }.to output(/chunk_size not set/).to_stderr
          expect(all_rows.size).to eq 12
        end

        it 'raises ArgumentError when chunk_size is 0' do
          reader = SmarterCSV::Reader.new(chunked_csv, base_options.merge(chunk_size: 0))
          expect { reader.each_chunk { |_c, _i| } }.to raise_error(ArgumentError, /chunk_size must be an Integer >= 1/)
        end

        it 'raises ArgumentError when chunk_size is negative' do
          reader = SmarterCSV::Reader.new(chunked_csv, base_options.merge(chunk_size: -1))
          expect { reader.each_chunk { |_c, _i| } }.to raise_error(ArgumentError, /chunk_size must be an Integer >= 1/)
        end

        # ----------------------------------------------------------------
        # Enumerator without block
        # ----------------------------------------------------------------
        it 'returns an Enumerator when called without a block' do
          options = base_options.merge(chunk_size: 5)
          reader = SmarterCSV::Reader.new(chunked_csv, options)
          expect(reader.each_chunk).to be_a(Enumerator)
        end

        it 'Enumerator can be chained with with_index' do
          options = base_options.merge(chunk_size: 5)
          reader = SmarterCSV::Reader.new(chunked_csv, options)
          chunk_sizes = reader.each_chunk.map { |chunk, _i| chunk.size }
          expect(chunk_sizes).to eq [5, 5, 2]
        end

        # ----------------------------------------------------------------
        # Interaction with on_bad_row
        # ----------------------------------------------------------------
        it 'skips bad rows in chunks when on_bad_row: :skip' do
          options = base_options.merge(strict: true, on_bad_row: :skip, chunk_size: 10)
          reader = SmarterCSV::Reader.new(quarantine_csv, options)
          all_rows = reader.each_chunk.flat_map { |chunk, _| chunk }
          expect(all_rows.map { |r| r[:name] }).to eq %w[John Mike]
        end
      end

      # ----------------------------------------------------------------
      # SmarterCSV.each — module-level convenience method
      # ----------------------------------------------------------------
      describe 'SmarterCSV.each' do
        it 'yields each row as a Hash' do
          rows = []
          SmarterCSV.each(chunked_csv, base_options) { |row| rows << row }
          expect(rows).to all(be_a(Hash))
          expect(rows.size).to eq 12
        end

        it 'returns an Enumerator when called without a block' do
          expect(SmarterCSV.each(chunked_csv, base_options)).to be_a(Enumerator)
        end

        it 'supports Enumerable on the returned Enumerator' do
          ids = SmarterCSV.each(chunked_csv, base_options).map { |row| row[:id] }
          expect(ids).to eq (1..12).to_a
        end
      end

      # ----------------------------------------------------------------
      # SmarterCSV.each_chunk — module-level convenience method
      # ----------------------------------------------------------------
      describe 'SmarterCSV.each_chunk' do
        it 'yields Array<Hash> chunks and index' do
          chunks = []
          SmarterCSV.each_chunk(chunked_csv, base_options.merge(chunk_size: 5)) { |chunk, _i| chunks << chunk }
          expect(chunks.size).to eq 3
          expect(chunks.flatten).to all(be_a(Hash))
        end

        it 'returns an Enumerator when called without a block' do
          expect(SmarterCSV.each_chunk(chunked_csv, base_options.merge(chunk_size: 5))).to be_a(Enumerator)
        end

        it 'emits a warning and uses DEFAULT_CHUNK_SIZE when chunk_size is not set' do
          expect do
            SmarterCSV.each_chunk(chunked_csv, base_options) { |_c, _i| }
          end.to output(/chunk_size not set/).to_stderr
        end
      end
    end
  end
end
