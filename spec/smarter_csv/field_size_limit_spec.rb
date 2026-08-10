# frozen_string_literal: true

describe 'field_size_limit option' do
  let(:fixture_path) { 'spec/fixtures' }

  # field_size_limit is OVERRUN PROTECTION — a hard upper bound (in bytes) against runaway
  # fields (never-closing quotes, crafted huge fields), not a per-field validation tool.
  # It is therefore never meant to be small: values below 4096 raise a ValidationError.
  MINIMUM_LIMIT = 4096

  # ---------------------------------------------------------------------------
  # Option validation
  # ---------------------------------------------------------------------------

  describe 'option validation' do
    it 'accepts nil (default — no limit)' do
      expect { SmarterCSV.process("#{fixture_path}/basic.csv", field_size_limit: nil) }.not_to raise_error
    end

    it 'accepts the minimum value 4096' do
      expect { SmarterCSV.process("#{fixture_path}/basic.csv", field_size_limit: 4096) }.not_to raise_error
    end

    it 'accepts a large Integer' do
      expect { SmarterCSV.process("#{fixture_path}/basic.csv", field_size_limit: 1_000_000) }.not_to raise_error
    end

    it 'raises ValidationError for values below 4096 (overrun protection, not field validation)' do
      [4095, 1024, 100, 1].each do |too_small|
        expect { SmarterCSV.process("#{fixture_path}/basic.csv", field_size_limit: too_small) }
          .to raise_error(SmarterCSV::ValidationError, /invalid field_size_limit/)
      end
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
      expect { SmarterCSV.process("#{fixture_path}/basic.csv", field_size_limit: "4096") }
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
        csv = StringIO.new("id,payload\n1,\"#{'x' * (MINIMUM_LIMIT + 100)}\"\n")
        expect { SmarterCSV.process(csv, opts.merge(field_size_limit: MINIMUM_LIMIT)) }
          .to raise_error(SmarterCSV::FieldSizeLimitExceeded)
      end

      it 'does not raise when the field is exactly at the limit' do
        csv = StringIO.new("id,payload\n1,\"#{'x' * MINIMUM_LIMIT}\"\n")
        expect { SmarterCSV.process(csv, opts.merge(field_size_limit: MINIMUM_LIMIT)) }.not_to raise_error
      end

      # -----------------------------------------------------------------------
      # Attack vector 1b: huge DIGIT-ONLY field — must raise BEFORE the expensive
      # conversion to a huge Integer (Bignum conversion cost grows with the square
      # of the digit count — the exact overrun this option exists to prevent).
      # -----------------------------------------------------------------------

      it 'raises FieldSizeLimitExceeded for an oversized digit-only field (not converted to a number)' do
        csv = StringIO.new("id,amount\n1,#{'9' * (MINIMUM_LIMIT * 2)}\n")
        expect { SmarterCSV.process(csv, opts.merge(field_size_limit: MINIMUM_LIMIT)) }
          .to raise_error(SmarterCSV::FieldSizeLimitExceeded)
      end

      it 'still converts digit fields under the limit to numbers' do
        csv = StringIO.new("id,amount\n1,42\n")
        data = SmarterCSV.process(csv, opts.merge(field_size_limit: MINIMUM_LIMIT))
        expect(data.first[:amount]).to eql 42
      end

      # -----------------------------------------------------------------------
      # Many small fields — total row bytes > limit, but no individual field exceeds it
      # -----------------------------------------------------------------------

      it 'does not raise when many small fields together exceed the limit but no single field does' do
        # 10 fields of ~1000 bytes each → row ~10KB; limit 4096 → no field is 4096+ bytes
        headers = (1..10).map { |i| "col#{i}" }.join(',')
        values  = (1..10).map { 'x' * 1000 }.join(',')
        csv = StringIO.new("#{headers}\n#{values}\n")
        expect { SmarterCSV.process(csv, opts.merge(field_size_limit: MINIMUM_LIMIT)) }.not_to raise_error
      end

      # -----------------------------------------------------------------------
      # Attack vector 2 & 3: runaway multiline / never-closing quote
      # -----------------------------------------------------------------------

      it 'raises FieldSizeLimitExceeded when a multiline field accumulates beyond the limit' do
        # Quoted field spans many physical lines without closing
        big_line = "#{'x' * 2000}\n"
        lines = ["id,notes\n", "1,\"line one\n", big_line, big_line, big_line]
        csv = StringIO.new(lines.join)
        expect { SmarterCSV.process(csv, opts.merge(field_size_limit: MINIMUM_LIMIT)) }
          .to raise_error(SmarterCSV::FieldSizeLimitExceeded)
      end

      it 'raises FieldSizeLimitExceeded for a never-closing quoted field (rest of file eaten)' do
        filler = "#{'y' * 3000}\n"
        csv = StringIO.new("id,comment\n1,\"this quote never closes\n#{filler}#{filler}")
        expect { SmarterCSV.process(csv, opts.merge(field_size_limit: MINIMUM_LIMIT)) }
          .to raise_error(SmarterCSV::FieldSizeLimitExceeded)
      end

      # -----------------------------------------------------------------------
      # on_bad_row: :skip — FieldSizeLimitExceeded treated as a bad row
      # -----------------------------------------------------------------------

      it 'skips the oversized row and continues when on_bad_row: :skip' do
        csv = StringIO.new("id,payload\n1,\"#{'x' * (MINIMUM_LIMIT + 100)}\"\n2,small\n")
        data = SmarterCSV.process(csv, opts.merge(field_size_limit: MINIMUM_LIMIT, on_bad_row: :skip))
        # Row 1 is skipped due to oversized field; row 2 is returned
        expect(data.size).to eq 1
        expect(data.first[:id]).to eq 2
      end

      it 'collects the oversized row error when on_bad_row: :collect' do
        csv = StringIO.new("id,payload\n1,\"#{'x' * (MINIMUM_LIMIT + 100)}\"\n2,ok\n")
        reader = SmarterCSV::Reader.new(csv, opts.merge(field_size_limit: MINIMUM_LIMIT, on_bad_row: :collect))
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
