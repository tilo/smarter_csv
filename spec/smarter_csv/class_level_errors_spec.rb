# frozen_string_literal: true

# Tests for SmarterCSV.errors — thread-local error state exposed after class-level API calls.

fixture_path = 'spec/fixtures'

describe 'SmarterCSV.errors — class-level error access' do
  let(:clean_csv)    { "#{fixture_path}/bad_row_quarantine.csv" }      # 1 bad row
  let(:multi_csv)    { "#{fixture_path}/bad_row_quarantine_multi.csv" } # 2 bad rows

  # -------------------------------------------------------------------------
  # Initial state
  # -------------------------------------------------------------------------
  describe 'before any call' do
    it 'returns an empty hash' do
      Thread.current[:smarter_csv_recent_errors] = nil # simulate a fresh thread
      expect(SmarterCSV.errors).to eq({})
    end
  end

  # -------------------------------------------------------------------------
  # .process
  # -------------------------------------------------------------------------
  describe '.process' do
    [true, false].each do |accel|
      context "acceleration: #{accel}" do
        let(:base_options) { { acceleration: accel, missing_headers: :raise } }

        it 'returns {} when there are no bad rows' do
          SmarterCSV.process("#{fixture_path}/sample.csv", { acceleration: accel })
          expect(SmarterCSV.errors).to eq({})
        end

        it 'clears errors from the previous call at the start of a new call' do
          SmarterCSV.process(clean_csv, base_options.merge(on_bad_row: :skip))
          expect(SmarterCSV.errors[:bad_row_count]).to eq(1)

          SmarterCSV.process("#{fixture_path}/sample.csv", { acceleration: accel })
          expect(SmarterCSV.errors).to eq({})
        end

        context 'on_bad_row: :skip' do
          it 'exposes bad_row_count' do
            SmarterCSV.process(clean_csv, base_options.merge(on_bad_row: :skip))
            expect(SmarterCSV.errors[:bad_row_count]).to eq(1)
            expect(SmarterCSV.errors[:bad_rows]).to be_nil
          end

          it 'counts multiple bad rows' do
            SmarterCSV.process(multi_csv, base_options.merge(on_bad_row: :skip))
            expect(SmarterCSV.errors[:bad_row_count]).to eq(2)
          end
        end

        context 'on_bad_row: :collect' do
          it 'exposes bad_row_count and bad_rows array' do
            SmarterCSV.process(clean_csv, base_options.merge(on_bad_row: :collect))
            expect(SmarterCSV.errors[:bad_row_count]).to eq(1)
            expect(SmarterCSV.errors[:bad_rows].size).to eq(1)
          end

          it 'bad_row_count equals bad_rows.size' do
            SmarterCSV.process(multi_csv, base_options.merge(on_bad_row: :collect))
            expect(SmarterCSV.errors[:bad_row_count]).to eq(SmarterCSV.errors[:bad_rows].size)
          end
        end

        context 'on_bad_row: :raise (default)' do
          it 'errors is {} before the raise' do
            expect {
              SmarterCSV.process(clean_csv, base_options.merge(on_bad_row: :raise))
            }.to raise_error(SmarterCSV::Error)
            # errors were cleared at start of the call
            expect(SmarterCSV.errors).to eq({})
          end
        end

        context 'with chunk_size' do
          it 'exposes bad_row_count across chunks' do
            SmarterCSV.process(multi_csv, base_options.merge(on_bad_row: :skip, chunk_size: 1)) do |_chunk|
              # process each chunk
            end
            expect(SmarterCSV.errors[:bad_row_count]).to eq(2)
          end
        end
      end
    end
  end

  # -------------------------------------------------------------------------
  # .parse
  # -------------------------------------------------------------------------
  describe '.parse' do
    let(:bad_csv_string)   { "name,age\nAlice,30\nBob,25,EXTRA\nCarol,40" }
    let(:clean_csv_string) { "name,age\nAlice,30\nBob,25" }

    [true, false].each do |accel|
      context "acceleration: #{accel}" do
        let(:base_options) { { acceleration: accel, missing_headers: :raise } }

        it 'returns {} when there are no bad rows' do
          SmarterCSV.parse(clean_csv_string, base_options)
          expect(SmarterCSV.errors).to eq({})
        end

        it 'exposes bad_row_count via on_bad_row: :skip' do
          SmarterCSV.parse(bad_csv_string, base_options.merge(on_bad_row: :skip))
          expect(SmarterCSV.errors[:bad_row_count]).to eq(1)
          expect(SmarterCSV.errors[:bad_rows]).to be_nil
        end

        it 'exposes bad_rows array via on_bad_row: :collect' do
          SmarterCSV.parse(bad_csv_string, base_options.merge(on_bad_row: :collect))
          expect(SmarterCSV.errors[:bad_row_count]).to eq(1)
          expect(SmarterCSV.errors[:bad_rows].size).to eq(1)
        end

        it 'clears errors from the previous call' do
          SmarterCSV.parse(bad_csv_string, base_options.merge(on_bad_row: :skip))
          expect(SmarterCSV.errors[:bad_row_count]).to eq(1)

          SmarterCSV.parse(clean_csv_string, base_options)
          expect(SmarterCSV.errors).to eq({})
        end
      end
    end
  end

  # -------------------------------------------------------------------------
  # .each
  # -------------------------------------------------------------------------
  describe '.each' do
    [true, false].each do |accel|
      context "acceleration: #{accel}" do
        let(:base_options) { { acceleration: accel, missing_headers: :raise } }

        it 'returns {} when there are no bad rows' do
          SmarterCSV.each("#{fixture_path}/sample.csv", { acceleration: accel }) { |_row| }
          expect(SmarterCSV.errors).to eq({})
        end

        it 'exposes bad_row_count via on_bad_row: :skip' do
          SmarterCSV.each(clean_csv, base_options.merge(on_bad_row: :skip)) { |_row| }
          expect(SmarterCSV.errors[:bad_row_count]).to eq(1)
          expect(SmarterCSV.errors[:bad_rows]).to be_nil
        end

        it 'exposes bad_rows array via on_bad_row: :collect' do
          SmarterCSV.each(clean_csv, base_options.merge(on_bad_row: :collect)) { |_row| }
          expect(SmarterCSV.errors[:bad_row_count]).to eq(1)
          expect(SmarterCSV.errors[:bad_rows].size).to eq(1)
        end

        it 'clears errors from the previous call' do
          SmarterCSV.each(clean_csv, base_options.merge(on_bad_row: :skip)) { |_row| }
          expect(SmarterCSV.errors[:bad_row_count]).to eq(1)

          SmarterCSV.each("#{fixture_path}/sample.csv", { acceleration: accel }) { |_row| }
          expect(SmarterCSV.errors).to eq({})
        end
      end
    end
  end

  # -------------------------------------------------------------------------
  # .each_chunk
  # -------------------------------------------------------------------------
  describe '.each_chunk' do
    [true, false].each do |accel|
      context "acceleration: #{accel}" do
        let(:base_options) { { acceleration: accel, chunk_size: 2, missing_headers: :raise } }

        it 'returns {} when there are no bad rows' do
          SmarterCSV.each_chunk("#{fixture_path}/sample.csv", { acceleration: accel, chunk_size: 2 }) { |_chunk| }
          expect(SmarterCSV.errors).to eq({})
        end

        it 'exposes bad_row_count via on_bad_row: :skip' do
          SmarterCSV.each_chunk(clean_csv, base_options.merge(on_bad_row: :skip)) { |_chunk| }
          expect(SmarterCSV.errors[:bad_row_count]).to eq(1)
          expect(SmarterCSV.errors[:bad_rows]).to be_nil
        end

        it 'exposes bad_rows array via on_bad_row: :collect' do
          SmarterCSV.each_chunk(multi_csv, base_options.merge(on_bad_row: :collect)) { |_chunk| }
          expect(SmarterCSV.errors[:bad_row_count]).to eq(2)
          expect(SmarterCSV.errors[:bad_rows].size).to eq(2)
        end

        it 'clears errors from the previous call' do
          SmarterCSV.each_chunk(clean_csv, base_options.merge(on_bad_row: :skip)) { |_chunk| }
          expect(SmarterCSV.errors[:bad_row_count]).to eq(1)

          SmarterCSV.each_chunk("#{fixture_path}/sample.csv", { acceleration: accel, chunk_size: 2 }) { |_chunk| }
          expect(SmarterCSV.errors).to eq({})
        end
      end
    end
  end

  # -------------------------------------------------------------------------
  # Thread isolation
  # -------------------------------------------------------------------------
  describe 'thread isolation' do
    let(:bad_row_options) { { on_bad_row: :skip, missing_headers: :raise } }

    it 'does not leak errors across threads' do
      SmarterCSV.process(clean_csv, bad_row_options)
      expect(SmarterCSV.errors[:bad_row_count]).to eq(1)

      errors_in_other_thread = nil
      Thread.new do
        # Other thread has not called process — should see empty hash
        errors_in_other_thread = SmarterCSV.errors
      end.join

      expect(errors_in_other_thread).to eq({})
    end

    it 'each thread tracks its own errors independently' do
      results = {}

      t1 = Thread.new do
        SmarterCSV.process(multi_csv, bad_row_options)
        results[:t1] = SmarterCSV.errors[:bad_row_count]
      end

      t2 = Thread.new do
        SmarterCSV.process(clean_csv, bad_row_options)
        results[:t2] = SmarterCSV.errors[:bad_row_count]
      end

      t1.join
      t2.join

      expect(results[:t1]).to eq(2)
      expect(results[:t2]).to eq(1)
    end
  end
end
