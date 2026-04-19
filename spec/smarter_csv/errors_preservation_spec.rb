# frozen_string_literal: true

# Regression tests for: SmarterCSV.errors loses collected records when
# processing raises mid-stream.
#
# Before the fix, the class-level `SmarterCSV.errors` was only populated on
# the happy path — if processing raised (e.g. TooManyBadRows), the thread-local
# state stayed at `{}` from the start-of-call reset, discarding every bad row
# the reader had already collected. This defeated the on_bad_row: :collect +
# bad_row_limit: feature at the exact threshold where it should have helped.
#
# See loosing_errors_bug.md for the full write-up.

describe 'SmarterCSV.errors — preservation across exceptions' do
  # Headers = 2 cols. Data rows with an extra col are "bad" only when
  # missing_headers: :raise (default :auto auto-names extra cols instead).
  let(:base_options) { { missing_headers: :raise } }
  let(:dirty_csv_string) do
    header = "a,b\n"
    bad_rows = Array.new(150) { "x,y,EXTRA\n" }.join
    header + bad_rows
  end

  context 'when bad_row_limit is exceeded (TooManyBadRows raised)' do
    it 'preserves collected bad_rows up to the limit' do
      expect {
        SmarterCSV.parse(dirty_csv_string, base_options.merge(on_bad_row: :collect, bad_row_limit: 50))
      }.to raise_error(SmarterCSV::TooManyBadRows)

      expect(SmarterCSV.errors[:bad_rows]).to be_an(Array)
      expect(SmarterCSV.errors[:bad_rows].size).to be >= 50
      expect(SmarterCSV.errors[:bad_row_count]).to be >= 51
    end

    it 'preserves bad_row_count when on_bad_row: :skip + bad_row_limit' do
      expect {
        SmarterCSV.parse(dirty_csv_string, base_options.merge(on_bad_row: :skip, bad_row_limit: 20))
      }.to raise_error(SmarterCSV::TooManyBadRows)

      expect(SmarterCSV.errors[:bad_row_count]).to be >= 21
    end
  end

  context 'when the user block raises mid-processing' do
    it 'preserves errors accumulated before the block raised' do
      # Bad row comes first (row 2), then a good row that triggers the block raise.
      dirty = "a,b\nbad,row,extra\nok1,ok2\n"

      expect {
        SmarterCSV.parse(dirty, base_options.merge(on_bad_row: :collect)) { |_row| raise 'boom' }
      }.to raise_error(/boom/)

      # Without the fix this would be {} because the `reader.errors` copy
      # happens after reader.process returns, which it never does when the
      # user's block raises.
      expect(SmarterCSV.errors).not_to eq({})
      expect(SmarterCSV.errors[:bad_row_count]).to eq(1)
    end
  end

  context 'when Reader.new raises (e.g. bad input path)' do
    it 'leaves SmarterCSV.errors as an empty hash (nothing to preserve)' do
      expect {
        SmarterCSV.process('/tmp/definitely_does_not_exist_xyz.csv')
      }.to raise_error(StandardError)

      expect(SmarterCSV.errors).to eq({})
    end
  end

  context '.each' do
    # Fixture layout: good, bad, bad, good
    let(:fixture) { 'spec/fixtures/bad_row_quarantine_multi.csv' }

    it 'preserves collected bad_rows when bad_row_limit is exceeded (:collect)' do
      expect {
        SmarterCSV.each(fixture, base_options.merge(on_bad_row: :collect, bad_row_limit: 1)) { |_row| }
      }.to raise_error(SmarterCSV::TooManyBadRows)

      expect(SmarterCSV.errors[:bad_rows]).to be_an(Array)
      expect(SmarterCSV.errors[:bad_rows].size).to be >= 1
    end

    it 'preserves bad_row_count when bad_row_limit is exceeded (:skip)' do
      expect {
        SmarterCSV.each(fixture, base_options.merge(on_bad_row: :skip, bad_row_limit: 1)) { |_row| }
      }.to raise_error(SmarterCSV::TooManyBadRows)

      expect(SmarterCSV.errors[:bad_row_count]).to be >= 2
    end

    it 'preserves errors when the user block raises' do
      # Raise on the 2nd yield so the two bad rows between the first and
      # second good rows have already been collected before the block blows up.
      count = 0
      expect {
        SmarterCSV.each(fixture, base_options.merge(on_bad_row: :collect)) do |_row|
          count += 1
          raise 'boom' if count >= 2
        end
      }.to raise_error(/boom/)

      expect(SmarterCSV.errors[:bad_row_count]).to eq(2)
      expect(SmarterCSV.errors[:bad_rows].size).to eq(2)
    end

    it 'leaves SmarterCSV.errors as {} when Reader.new raises' do
      expect {
        SmarterCSV.each('/tmp/definitely_does_not_exist_xyz.csv') { |_row| }
      }.to raise_error(StandardError)

      expect(SmarterCSV.errors).to eq({})
    end
  end

  context '.each_chunk' do
    let(:fixture) { 'spec/fixtures/bad_row_quarantine_multi.csv' }

    it 'preserves collected bad_rows when bad_row_limit is exceeded (:collect)' do
      expect {
        SmarterCSV.each_chunk(fixture, base_options.merge(on_bad_row: :collect, bad_row_limit: 1, chunk_size: 1)) { |_chunk| }
      }.to raise_error(SmarterCSV::TooManyBadRows)

      expect(SmarterCSV.errors[:bad_rows]).to be_an(Array)
      expect(SmarterCSV.errors[:bad_rows].size).to be >= 1
    end

    it 'preserves bad_row_count when bad_row_limit is exceeded (:skip)' do
      expect {
        SmarterCSV.each_chunk(fixture, base_options.merge(on_bad_row: :skip, bad_row_limit: 1, chunk_size: 1)) { |_chunk| }
      }.to raise_error(SmarterCSV::TooManyBadRows)

      expect(SmarterCSV.errors[:bad_row_count]).to be >= 2
    end

    it 'preserves errors when the user block raises' do
      # chunk_size: 1 → chunk 1 = [John], then Jane+Mike are bad rows,
      # then chunk 2 = [Bob] → raise. By that point 2 bad rows are collected.
      count = 0
      expect {
        SmarterCSV.each_chunk(fixture, base_options.merge(on_bad_row: :collect, chunk_size: 1)) do |_chunk|
          count += 1
          raise 'boom' if count >= 2
        end
      }.to raise_error(/boom/)

      expect(SmarterCSV.errors[:bad_row_count]).to eq(2)
      expect(SmarterCSV.errors[:bad_rows].size).to eq(2)
    end

    it 'leaves SmarterCSV.errors as {} when Reader.new raises' do
      expect {
        SmarterCSV.each_chunk('/tmp/definitely_does_not_exist_xyz.csv', chunk_size: 10) { |_chunk| }
      }.to raise_error(StandardError)

      expect(SmarterCSV.errors).to eq({})
    end
  end
end
