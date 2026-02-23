# frozen_string_literal: true

fixture_path = 'spec/fixtures'

[true, false].each do |bool|
  describe "column selection (only_headers: / except_headers:) with#{bool ? ' C-' : 'out '}acceleration" do
    let(:base_options) { { acceleration: bool } }

    # --- only_headers: ---

    context "only_headers:" do
      it 'returns only the requested columns' do
        data = SmarterCSV.process("#{fixture_path}/basic.csv", base_options.merge(only_headers: [:first_name, :last_name]))
        expect(data).not_to be_empty
        data.each do |row|
          expect(row.keys).to match_array([:first_name, :last_name])
        end
      end

      it 'accepts string input and normalizes to symbols' do
        data = SmarterCSV.process("#{fixture_path}/basic.csv", base_options.merge(only_headers: ['first_name', 'last_name']))
        data.each do |row|
          expect(row.keys).to match_array([:first_name, :last_name])
        end
      end

      it 'accepts a single symbol (not wrapped in an array)' do
        data = SmarterCSV.process("#{fixture_path}/basic.csv", base_options.merge(only_headers: :first_name))
        data.each do |row|
          expect(row.keys).to match_array([:first_name])
        end
      end

      it 'accepts a single string (not wrapped in an array)' do
        data = SmarterCSV.process("#{fixture_path}/basic.csv", base_options.merge(only_headers: 'first_name'))
        data.each do |row|
          expect(row.keys).to match_array([:first_name])
        end
      end

      it 'returns correct values for the selected columns' do
        data = SmarterCSV.process("#{fixture_path}/basic.csv", base_options.merge(only_headers: [:first_name]))
        expect(data.first[:first_name]).to eq('Dan')
      end

      it 'silently ignores column names not present in the file' do
        expect {
          data = SmarterCSV.process("#{fixture_path}/basic.csv", base_options.merge(only_headers: [:first_name, :nonexistent_column]))
          data.each { |row| expect(row.keys).not_to include(:nonexistent_column) }
        }.not_to raise_error
      end
    end

    # --- except_headers: ---

    context "except_headers:" do
      it 'excludes the specified columns' do
        data = SmarterCSV.process("#{fixture_path}/basic.csv", base_options.merge(except_headers: [:dogs, :cats, :birds, :fish]))
        data.each do |row|
          expect(row.keys).not_to include(:dogs, :cats, :birds, :fish)
          expect(row.keys).to include(:first_name, :last_name)
        end
      end

      it 'accepts string input and normalizes to symbols' do
        data = SmarterCSV.process("#{fixture_path}/basic.csv", base_options.merge(except_headers: ['dogs', 'cats']))
        data.each { |row| expect(row.keys).not_to include(:dogs, :cats) }
      end

      it 'accepts a single symbol (not wrapped in an array)' do
        data = SmarterCSV.process("#{fixture_path}/basic.csv", base_options.merge(except_headers: :dogs))
        data.each { |row| expect(row.keys).not_to include(:dogs) }
      end

      it 'accepts a single string (not wrapped in an array)' do
        data = SmarterCSV.process("#{fixture_path}/basic.csv", base_options.merge(except_headers: 'dogs'))
        data.each { |row| expect(row.keys).not_to include(:dogs) }
      end

      it 'silently ignores column names not present in the file' do
        expect {
          data = SmarterCSV.process("#{fixture_path}/basic.csv", base_options.merge(except_headers: [:nonexistent_column]))
          data.each { |row| expect(row.keys).to include(:first_name, :last_name) }
        }.not_to raise_error
      end
    end

    # --- mutual exclusion ---

    it 'raises ValidationError when both only_headers: and except_headers: are given' do
      expect {
        SmarterCSV.process("#{fixture_path}/basic.csv", base_options.merge(only_headers: [:first_name], except_headers: [:last_name]))
      }.to raise_error(SmarterCSV::ValidationError, /cannot use both/)
    end

    # --- interaction with key_mapping ---

    context "only_headers: uses post-mapping names" do
      it 'filters by the mapped name, not the original header' do
        options = base_options.merge(
          key_mapping: { first_name: :given_name, last_name: :surname },
          only_headers: [:given_name]
        )
        data = SmarterCSV.process("#{fixture_path}/basic.csv", options)
        data.each do |row|
          expect(row.keys).to eq([:given_name])
        end
        expect(data.first[:given_name]).to eq('Dan')
      end
    end

    context "except_headers: uses post-mapping names" do
      it 'excludes by the mapped name, not the original header' do
        options = base_options.merge(
          key_mapping: { first_name: :given_name, last_name: :surname },
          except_headers: [:surname]
        )
        data = SmarterCSV.process("#{fixture_path}/basic.csv", options)
        data.each do |row|
          expect(row.keys).not_to include(:surname, :last_name)
          expect(row.keys).to include(:given_name)
        end
      end
    end

    # --- interaction with with_line_numbers ---

    context "only_headers: with with_line_numbers: true" do
      it 'always includes :csv_line_number even when not in only_headers' do
        options = base_options.merge(only_headers: [:first_name], with_line_numbers: true)
        data = SmarterCSV.process("#{fixture_path}/basic.csv", options)
        data.each do |row|
          expect(row.keys).to include(:first_name, :csv_line_number)
        end
      end
    end

    context "except_headers: with with_line_numbers: true" do
      it 'always includes :csv_line_number even when not in except_headers' do
        options = base_options.merge(except_headers: [:last_name], with_line_numbers: true)
        data = SmarterCSV.process("#{fixture_path}/basic.csv", options)
        data.each do |row|
          expect(row.keys).to include(:first_name, :csv_line_number)
          expect(row.keys).not_to include(:last_name)
        end
      end
    end

    # --- interaction with extra columns (strict: false, the default) ---

    context "only_headers: with extra columns in data" do
      it 'silently drops extra columns not in only_headers' do
        # basic.csv has 6 columns; only_headers picks 2 — extras are just dropped
        data = SmarterCSV.process("#{fixture_path}/basic.csv", base_options.merge(only_headers: [:first_name, :last_name]))
        data.each do |row|
          expect(row.keys).to match_array([:first_name, :last_name])
        end
      end

      it 'raises HeaderSizeMismatch when strict: true and data has extra columns' do
        csv = "name,value\nAlice,1,unexpected_extra\n"
        expect {
          SmarterCSV.process(StringIO.new(csv), base_options.merge(only_headers: [:name], strict: true))
        }.to raise_error(SmarterCSV::HeaderSizeMismatch)
      end
    end

    # --- C slow path: quoted fields (exercises Section 5 of rb_parse_line_to_hash) ---

    context "with quoted field values (C slow path)" do
      let(:quoted_csv) { "name,notes,value\nAlice,\"hello, world\",42\nBob,plain,99\n" }

      it 'only_headers: correctly filters columns containing quoted values' do
        data = SmarterCSV.process(StringIO.new(quoted_csv), base_options.merge(only_headers: [:name, :value]))
        expect(data.map { |r| r[:name] }).to eq(%w[Alice Bob])
        expect(data.map { |r| r[:value] }).to eq([42, 99])
        data.each { |row| expect(row.keys).not_to include(:notes) }
      end

      it 'except_headers: correctly excludes columns containing quoted values' do
        data = SmarterCSV.process(StringIO.new(quoted_csv), base_options.merge(except_headers: [:notes]))
        data.each do |row|
          expect(row.keys).to include(:name, :value)
          expect(row.keys).not_to include(:notes)
        end
      end
    end

    # --- C slow path: multi-char separator (exercises Section 5 of rb_parse_line_to_hash) ---

    context "with multi-char separator (C slow path)" do
      let(:multisep_csv) { "name::notes::value\nAlice::hello::42\nBob::plain::99\n" }

      it 'only_headers: correctly filters columns with multi-char col_sep' do
        data = SmarterCSV.process(StringIO.new(multisep_csv), base_options.merge(col_sep: '::', only_headers: [:name, :value]))
        expect(data.map { |r| r[:name] }).to eq(%w[Alice Bob])
        expect(data.map { |r| r[:value] }).to eq([42, 99])
        data.each { |row| expect(row.keys).not_to include(:notes) }
      end

      it 'except_headers: correctly excludes columns with multi-char col_sep' do
        data = SmarterCSV.process(StringIO.new(multisep_csv), base_options.merge(col_sep: '::', except_headers: [:notes]))
        data.each do |row|
          expect(row.keys).to include(:name, :value)
          expect(row.keys).not_to include(:notes)
        end
      end
    end

    # --- C Section 7: nil-padding for short rows (remove_empty_values: false) ---

    context "with short rows and remove_empty_values: false" do
      # Row with fewer fields than headers triggers nil-padding in the C extension.
      # only_headers: must suppress padding for excluded columns.
      let(:short_row_csv) { "name,value,extra\nAlice,1\nBob,2,bonus\n" }

      it 'only_headers: does not pad excluded columns with nil' do
        data = SmarterCSV.process(StringIO.new(short_row_csv), base_options.merge(
          only_headers: [:name],
          remove_empty_values: false,
        ))
        data.each { |row| expect(row.keys).to match_array([:name]) }
        expect(data.map { |r| r[:name] }).to eq(%w[Alice Bob])
      end

      it 'except_headers: does not pad excluded columns with nil' do
        data = SmarterCSV.process(StringIO.new(short_row_csv), base_options.merge(
          except_headers: [:value, :extra],
          remove_empty_values: false,
        ))
        data.each do |row|
          expect(row.keys).to match_array([:name])
          expect(row.keys).not_to include(:value, :extra)
        end
      end
    end
  end
end
