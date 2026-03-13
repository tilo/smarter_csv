# frozen_string_literal: true

fixture_path = 'spec/fixtures'

describe 'Bad row quarantine (on_bad_row option)' do
  let(:quarantine_csv)       { "#{fixture_path}/bad_row_quarantine.csv" }
  let(:quarantine_multi_csv) { "#{fixture_path}/bad_row_quarantine_multi.csv" }
  let(:multiline_csv)        { "#{fixture_path}/bad_row_multiline.csv" }

  [true, false].each do |bool|
    context "with#{bool ? ' C-' : 'out '}acceleration" do
      let(:base_options) { { acceleration: bool, missing_headers: :raise } }

      # ------------------------------------------------------------------
      # Default behavior: :raise
      # ------------------------------------------------------------------
      context 'on_bad_row: :raise (default)' do
        it 'raises on the first bad row' do
          reader = SmarterCSV::Reader.new(quarantine_csv, base_options)
          expect { reader.process }.to raise_error(SmarterCSV::HeaderSizeMismatch)
        end

        it 'raises when on_bad_row: :raise is set explicitly' do
          reader = SmarterCSV::Reader.new(quarantine_csv, base_options.merge(on_bad_row: :raise))
          expect { reader.process }.to raise_error(SmarterCSV::HeaderSizeMismatch)
        end

        it 'stops processing on the first bad row — good rows before it are still yielded' do
          rows_yielded = []
          reader = SmarterCSV::Reader.new(quarantine_csv, base_options)
          expect do
            reader.process { |rows, _| rows_yielded.concat(rows) }
          end.to raise_error(SmarterCSV::Error)
          # John (row 2) is yielded before Jane (row 3) triggers the raise
          expect(rows_yielded.map { |r| r[:name] }).to eq %w[John]
        end

        it 'does not record anything in reader.errors' do
          reader = SmarterCSV::Reader.new(quarantine_csv, base_options)
          expect { reader.process }.to raise_error(SmarterCSV::Error)
          expect(reader.errors[:bad_row_count]).to be_nil
          expect(reader.errors[:bad_rows]).to be_nil
        end

        it 'raises with a message identifying the offending line' do
          reader = SmarterCSV::Reader.new(quarantine_csv, base_options)
          expect { reader.process }.to raise_error(SmarterCSV::HeaderSizeMismatch, /line \d+/)
        end
      end

      # ------------------------------------------------------------------
      # :skip — continue silently, count bad rows
      # ------------------------------------------------------------------
      context 'on_bad_row: :skip' do
        let(:options) { base_options.merge(on_bad_row: :skip) }

        it 'skips bad rows and returns only good rows' do
          reader = SmarterCSV::Reader.new(quarantine_csv, options)
          result = reader.process
          expect(result.map { |r| r[:name] }).to eq %w[John Mike]
        end

        it 'tracks the bad row count on reader.errors' do
          reader = SmarterCSV::Reader.new(quarantine_csv, options)
          reader.process
          expect(reader.errors[:bad_row_count]).to eq 1
        end

        it 'does not populate reader.errors[:bad_rows]' do
          reader = SmarterCSV::Reader.new(quarantine_csv, options)
          reader.process
          expect(reader.errors[:bad_rows]).to be_nil
        end

        it 'counts multiple bad rows' do
          reader = SmarterCSV::Reader.new(quarantine_multi_csv, options)
          reader.process
          expect(reader.errors[:bad_row_count]).to eq 2
        end
      end

      # ------------------------------------------------------------------
      # :collect — continue and gather structured error records
      # ------------------------------------------------------------------
      context 'on_bad_row: :collect' do
        let(:options) { base_options.merge(on_bad_row: :collect) }

        it 'returns only good rows' do
          reader = SmarterCSV::Reader.new(quarantine_csv, options)
          result = reader.process
          expect(result.map { |r| r[:name] }).to eq %w[John Mike]
        end

        it 'collects one error record for the bad row' do
          reader = SmarterCSV::Reader.new(quarantine_csv, options)
          reader.process
          expect(reader.errors[:bad_rows].size).to eq 1
        end

        it 'error record contains expected fields' do
          reader = SmarterCSV::Reader.new(quarantine_csv, options)
          reader.process
          rec = reader.errors[:bad_rows].first
          expect(rec[:csv_line_number]).to eq 3 # header=1, John=2, Jane=3
          expect(rec[:file_line_number]).to eq 3
          expect(rec[:file_lines_consumed]).to eq 1
          expect(rec[:error_class]).to eq SmarterCSV::HeaderSizeMismatch
          expect(rec[:error_message]).to be_a String
        end

        it 'includes raw_logical_line by default (collect_raw_lines: true)' do
          reader = SmarterCSV::Reader.new(quarantine_csv, options)
          reader.process
          rec = reader.errors[:bad_rows].first
          expect(rec[:raw_logical_line]).to include('Jane')
        end

        it 'omits raw_logical_line when collect_raw_lines: false' do
          reader = SmarterCSV::Reader.new(quarantine_csv, options.merge(collect_raw_lines: false))
          reader.process
          rec = reader.errors[:bad_rows].first
          expect(rec).not_to have_key(:raw_logical_line)
        end

        it 'collects multiple bad rows' do
          reader = SmarterCSV::Reader.new(quarantine_multi_csv, options)
          reader.process
          expect(reader.errors[:bad_rows].size).to eq 2
          expect(reader.errors[:bad_row_count]).to eq 2
        end
      end

      # ------------------------------------------------------------------
      # Callable — full control via lambda/proc
      # ------------------------------------------------------------------
      context 'on_bad_row: callable' do
        it 'calls the lambda with the error record for each bad row' do
          collected = []
          options = base_options.merge(on_bad_row: ->(rec) { collected << rec })

          reader = SmarterCSV::Reader.new(quarantine_csv, options)
          result = reader.process

          expect(result.map { |r| r[:name] }).to eq %w[John Mike]
          expect(collected.size).to eq 1
          expect(collected.first[:error_class]).to eq SmarterCSV::HeaderSizeMismatch
          expect(collected.first[:raw_logical_line]).to include('Jane')
        end

        it 'callable receives raw_logical_line even without :collect mode' do
          received = nil
          options = base_options.merge(on_bad_row: ->(rec) { received = rec })

          reader = SmarterCSV::Reader.new(quarantine_csv, options)
          reader.process
          expect(received[:raw_logical_line]).to be_a String
        end

        it 'callable does not receive raw_logical_line when collect_raw_lines: false' do
          received = nil
          options = base_options.merge(
            on_bad_row: ->(rec) { received = rec },
            collect_raw_lines: false
          )

          reader = SmarterCSV::Reader.new(quarantine_csv, options)
          reader.process
          expect(received).not_to have_key(:raw_logical_line)
        end

        it 'processes multiple bad rows calling the lambda each time' do
          count = 0
          options = base_options.merge(on_bad_row: ->(_rec) { count += 1 })

          reader = SmarterCSV::Reader.new(quarantine_multi_csv, options)
          reader.process
          expect(count).to eq 2
        end
      end

      # ------------------------------------------------------------------
      # bad_row_limit
      # ------------------------------------------------------------------
      context 'bad_row_limit' do
        it 'raises TooManyBadRows when limit is exceeded' do
          options = base_options.merge(on_bad_row: :skip, bad_row_limit: 1)
          reader = SmarterCSV::Reader.new(quarantine_multi_csv, options)
          expect { reader.process }.to raise_error(SmarterCSV::TooManyBadRows)
        end

        it 'does not raise when bad rows are within the limit' do
          options = base_options.merge(on_bad_row: :skip, bad_row_limit: 5)
          reader = SmarterCSV::Reader.new(quarantine_multi_csv, options)
          expect { reader.process }.not_to raise_error
        end
      end

      # ------------------------------------------------------------------
      # Multiline unterminated quote
      # ------------------------------------------------------------------
      context 'multiline unterminated quote' do
        it 'raises MalformedCSV by default' do
          reader = SmarterCSV::Reader.new(multiline_csv, { acceleration: bool })
          expect { reader.process }.to raise_error(SmarterCSV::MalformedCSV)
        end

        it 'skips the stitched multiline bad row and continues' do
          reader = SmarterCSV::Reader.new(multiline_csv, { acceleration: bool, on_bad_row: :collect })
          result = reader.process
          # John is good; Jane + Bob get stitched into an unclosed quote and fail at EOF
          expect(result.map { |r| r[:name] }).to eq %w[John]
          expect(reader.errors[:bad_rows].size).to eq 1
        end

        it 'records file_lines_consumed > 1 for multiline bad rows' do
          reader = SmarterCSV::Reader.new(multiline_csv, { acceleration: bool, on_bad_row: :collect })
          reader.process
          rec = reader.errors[:bad_rows].first
          expect(rec[:file_lines_consumed]).to be > 1
        end

        it 'raw_logical_line contains the stitched content' do
          reader = SmarterCSV::Reader.new(multiline_csv, { acceleration: bool, on_bad_row: :collect })
          reader.process
          rec = reader.errors[:bad_rows].first
          expect(rec[:raw_logical_line]).to include('Jane')
          expect(rec[:raw_logical_line]).to include('unclosed')
        end
      end

      # ------------------------------------------------------------------
      # Option validation
      # ------------------------------------------------------------------
      context 'option validation' do
        it 'raises ValidationError for an invalid on_bad_row value' do
          expect do
            SmarterCSV::Reader.new(quarantine_csv, { acceleration: bool, on_bad_row: :invalid })
          end.to raise_error(SmarterCSV::ValidationError)
        end
      end
    end
  end
end
