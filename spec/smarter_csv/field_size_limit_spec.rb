# frozen_string_literal: true

describe 'field_size_limit option' do
  let(:fixture_path) { 'spec/fixtures' }

  # ---------------------------------------------------------------------------
  # Option validation
  # ---------------------------------------------------------------------------

  describe 'option validation' do
    it 'accepts nil (default — no limit)' do
      expect { SmarterCSV.process("#{fixture_path}/basic.csv", field_size_limit: nil) }.not_to raise_error
    end

    it 'accepts a positive Integer' do
      expect { SmarterCSV.process("#{fixture_path}/basic.csv", field_size_limit: 1024) }.not_to raise_error
    end

    it 'raises ValidationError for zero' do
      expect { SmarterCSV.process("#{fixture_path}/basic.csv", field_size_limit: 0) }
        .to raise_error(SmarterCSV::ValidationError, /invalid field_size_limit/)
    end

    it 'raises ValidationError for a negative Integer' do
      expect { SmarterCSV.process("#{fixture_path}/basic.csv", field_size_limit: -1) }
        .to raise_error(SmarterCSV::ValidationError, /invalid field_size_limit/)
    end

    it 'raises ValidationError for a non-Integer' do
      expect { SmarterCSV.process("#{fixture_path}/basic.csv", field_size_limit: "1024") }
        .to raise_error(SmarterCSV::ValidationError, /invalid field_size_limit/)
    end
  end

  # ---------------------------------------------------------------------------
  # Normal operation — no limit fires
  # ---------------------------------------------------------------------------

  [true, false].each do |accel|
    describe "with acceleration: #{accel}" do
      let(:opts) { { acceleration: accel } }

      it 'processes normally when field_size_limit is nil' do
        data = SmarterCSV.process("#{fixture_path}/basic.csv", opts.merge(field_size_limit: nil))
        expect(data.size).to eq 5
      end

      it 'processes normally when all fields are well under the limit' do
        data = SmarterCSV.process("#{fixture_path}/basic.csv", opts.merge(field_size_limit: 10_000))
        expect(data.size).to eq 5
      end

      # -----------------------------------------------------------------------
      # Attack vector 1: huge inline field (single-line, quoted)
      # -----------------------------------------------------------------------

      it 'raises FieldSizeLimitExceeded when a single-line field exceeds the limit' do
        csv = StringIO.new("id,payload\n1,\"#{"x" * 200}\"\n")
        expect { SmarterCSV.process(csv, opts.merge(field_size_limit: 100)) }
          .to raise_error(SmarterCSV::FieldSizeLimitExceeded)
      end

      it 'does not raise when the field is exactly at the limit' do
        csv = StringIO.new("id,payload\n1,\"#{"x" * 100}\"\n")
        expect { SmarterCSV.process(csv, opts.merge(field_size_limit: 100)) }.not_to raise_error
      end

      # -----------------------------------------------------------------------
      # Many small fields — total row bytes > limit, but no individual field exceeds it
      # -----------------------------------------------------------------------

      it 'does not raise when many small fields together exceed the limit but no single field does' do
        # 10 fields of 20 bytes each → row ~220 bytes; limit 50 → no field is 50+ bytes
        headers = (1..10).map { |i| "col#{i}" }.join(',')
        values  = (1..10).map { "x" * 20 }.join(',')
        csv = StringIO.new("#{headers}\n#{values}\n")
        expect { SmarterCSV.process(csv, opts.merge(field_size_limit: 50)) }.not_to raise_error
      end

      # -----------------------------------------------------------------------
      # Attack vector 2 & 3: runaway multiline / never-closing quote
      # -----------------------------------------------------------------------

      it 'raises FieldSizeLimitExceeded when a multiline field accumulates beyond the limit' do
        # Quoted field spans many physical lines without closing
        lines = ["id,notes\n", "1,\"line one\n", "line two\n", "line three\n", "line four\n"]
        csv = StringIO.new(lines.join)
        # Each "line N\n" is ~8 bytes; limit of 30 bytes fires well before the field closes
        expect { SmarterCSV.process(csv, opts.merge(field_size_limit: 30)) }
          .to raise_error(SmarterCSV::FieldSizeLimitExceeded)
      end

      it 'raises FieldSizeLimitExceeded for a never-closing quoted field (rest of file eaten)' do
        csv = StringIO.new("id,comment\n1,\"this quote never closes\nrow two data\nrow three data\n")
        expect { SmarterCSV.process(csv, opts.merge(field_size_limit: 40)) }
          .to raise_error(SmarterCSV::FieldSizeLimitExceeded)
      end

      # -----------------------------------------------------------------------
      # on_bad_row: :skip — FieldSizeLimitExceeded treated as a bad row
      # -----------------------------------------------------------------------

      it 'skips the oversized row and continues when on_bad_row: :skip' do
        csv = StringIO.new("id,payload\n1,\"#{"x" * 200}\"\n2,small\n")
        data = SmarterCSV.process(csv, opts.merge(field_size_limit: 100, on_bad_row: :skip))
        # Row 1 is skipped due to oversized field; row 2 is returned
        expect(data.size).to eq 1
        expect(data.first[:id]).to eq 2
      end

      it 'collects the oversized row error when on_bad_row: :collect' do
        csv = StringIO.new("id,payload\n1,\"#{"x" * 200}\"\n2,ok\n")
        reader = SmarterCSV::Reader.new(csv, opts.merge(field_size_limit: 100, on_bad_row: :collect))
        data = reader.process
        expect(data.size).to eq 1
        expect(reader.errors[:bad_row_count]).to eq 1
        expect(reader.errors[:bad_rows].first[:error_class]).to eq SmarterCSV::FieldSizeLimitExceeded
      end

      # -----------------------------------------------------------------------
      # Multiline that fits within the limit should still parse correctly
      # -----------------------------------------------------------------------

      it 'parses a legitimate multiline field under the limit' do
        data = SmarterCSV.process(
          "#{fixture_path}/continuation_lines.csv",
          opts.merge(field_size_limit: 10_000)
        )
        expect(data.size).to eq 2
        expect(data[1][:description]).to include("World-renowned")
      end
    end
  end
end
