# frozen_string_literal: true

fixture_path = 'spec/fixtures'

[true, false].each do |bool|
  describe "column selection (headers: { only: } / { except: }) with#{bool ? ' C-' : 'out '}acceleration" do
    let(:base_options) { { acceleration: bool } }

    # --- headers: { only: } ---

    context "headers: { only: }" do
      it 'returns only the requested columns' do
        data = SmarterCSV.process("#{fixture_path}/basic.csv", base_options.merge(headers: { only: [:first_name, :last_name] }))
        expect(data).not_to be_empty
        data.each do |row|
          expect(row.keys).to match_array([:first_name, :last_name])
        end
      end

      it 'accepts string input and normalizes to symbols' do
        data = SmarterCSV.process("#{fixture_path}/basic.csv", base_options.merge(headers: { only: ['first_name', 'last_name'] }))
        data.each do |row|
          expect(row.keys).to match_array([:first_name, :last_name])
        end
      end

      it 'accepts a single symbol (not wrapped in an array)' do
        data = SmarterCSV.process("#{fixture_path}/basic.csv", base_options.merge(headers: { only: :first_name }))
        data.each do |row|
          expect(row.keys).to match_array([:first_name])
        end
      end

      it 'accepts a single string (not wrapped in an array)' do
        data = SmarterCSV.process("#{fixture_path}/basic.csv", base_options.merge(headers: { only: 'first_name' }))
        data.each do |row|
          expect(row.keys).to match_array([:first_name])
        end
      end

      it 'returns correct values for the selected columns' do
        data = SmarterCSV.process("#{fixture_path}/basic.csv", base_options.merge(headers: { only: [:first_name] }))
        expect(data.first[:first_name]).to eq('Dan')
      end

      it 'silently ignores column names not present in the file' do
        expect do
          data = SmarterCSV.process("#{fixture_path}/basic.csv", base_options.merge(headers: { only: [:first_name, :nonexistent_column] }))
          data.each { |row| expect(row.keys).not_to include(:nonexistent_column) }
        end.not_to raise_error
      end
    end

    # --- headers: { except: } ---

    context "headers: { except: }" do
      it 'excludes the specified columns' do
        data = SmarterCSV.process("#{fixture_path}/basic.csv", base_options.merge(headers: { except: [:dogs, :cats, :birds, :fish] }))
        data.each do |row|
          expect(row.keys).not_to include(:dogs, :cats, :birds, :fish)
          expect(row.keys).to include(:first_name, :last_name)
        end
      end

      it 'accepts string input and normalizes to symbols' do
        data = SmarterCSV.process("#{fixture_path}/basic.csv", base_options.merge(headers: { except: ['dogs', 'cats'] }))
        data.each { |row| expect(row.keys).not_to include(:dogs, :cats) }
      end

      it 'accepts a single symbol (not wrapped in an array)' do
        data = SmarterCSV.process("#{fixture_path}/basic.csv", base_options.merge(headers: { except: :dogs }))
        data.each { |row| expect(row.keys).not_to include(:dogs) }
      end

      it 'accepts a single string (not wrapped in an array)' do
        data = SmarterCSV.process("#{fixture_path}/basic.csv", base_options.merge(headers: { except: 'dogs' }))
        data.each { |row| expect(row.keys).not_to include(:dogs) }
      end

      it 'silently ignores column names not present in the file' do
        expect do
          data = SmarterCSV.process("#{fixture_path}/basic.csv", base_options.merge(headers: { except: [:nonexistent_column] }))
          data.each { |row| expect(row.keys).to include(:first_name, :last_name) }
        end.not_to raise_error
      end
    end

    # --- mutual exclusion ---

    it 'raises ValidationError when both headers: { only: } and headers: { except: } are given' do
      expect do
        SmarterCSV.process("#{fixture_path}/basic.csv", base_options.merge(headers: { only: [:first_name], except: [:last_name] }))
      end.to raise_error(SmarterCSV::ValidationError, /cannot use both/)
    end

    # --- element type validation ---

    it 'raises ValidationError when headers: { only: } contains non-String/Symbol elements' do
      expect do
        SmarterCSV.process("#{fixture_path}/basic.csv", base_options.merge(headers: { only: [1, 2] }))
      end.to raise_error(SmarterCSV::ValidationError, /only.*String or Symbol/i)
    end

    it 'raises ValidationError when headers: { except: } contains non-String/Symbol elements' do
      expect do
        SmarterCSV.process("#{fixture_path}/basic.csv", base_options.merge(headers: { except: [1, 2] }))
      end.to raise_error(SmarterCSV::ValidationError, /except.*String or Symbol/i)
    end

    # --- interaction with key_mapping ---

    context "headers: { only: } uses post-mapping names" do
      it 'filters by the mapped name, not the original header' do
        options = base_options.merge(
          key_mapping: { first_name: :given_name, last_name: :surname },
          headers: { only: [:given_name] }
        )
        data = SmarterCSV.process("#{fixture_path}/basic.csv", options)
        data.each do |row|
          expect(row.keys).to eq([:given_name])
        end
        expect(data.first[:given_name]).to eq('Dan')
      end
    end

    context "headers: { except: } uses post-mapping names" do
      it 'excludes by the mapped name, not the original header' do
        options = base_options.merge(
          key_mapping: { first_name: :given_name, last_name: :surname },
          headers: { except: [:surname] }
        )
        data = SmarterCSV.process("#{fixture_path}/basic.csv", options)
        data.each do |row|
          expect(row.keys).not_to include(:surname, :last_name)
          expect(row.keys).to include(:given_name)
        end
      end
    end

    # --- interaction with with_line_numbers ---

    context "headers: { only: } with with_line_numbers: true" do
      it 'always includes :csv_line_number even when not in the only list' do
        options = base_options.merge(headers: { only: [:first_name] }, with_line_numbers: true)
        data = SmarterCSV.process("#{fixture_path}/basic.csv", options)
        data.each do |row|
          expect(row.keys).to include(:first_name, :csv_line_number)
        end
      end
    end

    context "headers: { except: } with with_line_numbers: true" do
      it 'always includes :csv_line_number even when not in the except list' do
        options = base_options.merge(headers: { except: [:last_name] }, with_line_numbers: true)
        data = SmarterCSV.process("#{fixture_path}/basic.csv", options)
        data.each do |row|
          expect(row.keys).to include(:first_name, :csv_line_number)
          expect(row.keys).not_to include(:last_name)
        end
      end
    end

    # --- interaction with extra columns (missing_headers: :auto, the default) ---

    context "headers: { only: } with extra columns in data" do
      it 'silently drops extra columns not in the only list' do
        # basic.csv has 6 columns; headers: { only: } picks 2 — extras are just dropped
        data = SmarterCSV.process("#{fixture_path}/basic.csv", base_options.merge(headers: { only: [:first_name, :last_name] }))
        data.each do |row|
          expect(row.keys).to match_array([:first_name, :last_name])
        end
      end

      it 'raises HeaderSizeMismatch when missing_headers: :raise and data has extra columns' do
        csv = "name,value\nAlice,1,unexpected_extra\n"
        expect do
          SmarterCSV.process(StringIO.new(csv), base_options.merge(headers: { only: [:name] }, missing_headers: :raise))
        end.to raise_error(SmarterCSV::HeaderSizeMismatch)
      end
    end

    # --- C slow path: quoted fields (exercises Section 5 of rb_parse_line_to_hash) ---

    context "with quoted field values (C slow path)" do
      let(:quoted_csv) { "name,notes,value\nAlice,\"hello, world\",42\nBob,plain,99\n" }

      it 'headers: { only: } correctly filters columns containing quoted values' do
        data = SmarterCSV.process(StringIO.new(quoted_csv), base_options.merge(headers: { only: [:name, :value] }))
        expect(data.map { |r| r[:name] }).to eq(%w[Alice Bob])
        expect(data.map { |r| r[:value] }).to eq([42, 99])
        data.each { |row| expect(row.keys).not_to include(:notes) }
      end

      it 'headers: { except: } correctly excludes columns containing quoted values' do
        data = SmarterCSV.process(StringIO.new(quoted_csv), base_options.merge(headers: { except: [:notes] }))
        data.each do |row|
          expect(row.keys).to include(:name, :value)
          expect(row.keys).not_to include(:notes)
        end
      end
    end

    # --- C slow path: multi-char separator (exercises Section 5 of rb_parse_line_to_hash) ---

    context "with multi-char separator (C slow path)" do
      let(:multisep_csv) { "name::notes::value\nAlice::hello::42\nBob::plain::99\n" }

      it 'headers: { only: } correctly filters columns with multi-char col_sep' do
        data = SmarterCSV.process(StringIO.new(multisep_csv), base_options.merge(col_sep: '::', headers: { only: [:name, :value] }))
        expect(data.map { |r| r[:name] }).to eq(%w[Alice Bob])
        expect(data.map { |r| r[:value] }).to eq([42, 99])
        data.each { |row| expect(row.keys).not_to include(:notes) }
      end

      it 'headers: { except: } correctly excludes columns with multi-char col_sep' do
        data = SmarterCSV.process(StringIO.new(multisep_csv), base_options.merge(col_sep: '::', headers: { except: [:notes] }))
        data.each do |row|
          expect(row.keys).to include(:name, :value)
          expect(row.keys).not_to include(:notes)
        end
      end
    end

    # --- C Section 7: nil-padding for short rows (remove_empty_values: false) ---

    context "with short rows and remove_empty_values: false" do
      # Row with fewer fields than headers triggers nil-padding in the C extension.
      # headers: { only: } must suppress padding for excluded columns.
      let(:short_row_csv) { "name,value,extra\nAlice,1\nBob,2,bonus\n" }

      it 'headers: { only: } does not pad excluded columns with nil' do
        data = SmarterCSV.process(StringIO.new(short_row_csv), base_options.merge(
                                                                 headers: { only: [:name] },
                                                                 remove_empty_values: false
                                                               ))
        data.each { |row| expect(row.keys).to match_array([:name]) }
        expect(data.map { |r| r[:name] }).to eq(%w[Alice Bob])
      end

      it 'headers: { except: } does not pad excluded columns with nil' do
        data = SmarterCSV.process(StringIO.new(short_row_csv), base_options.merge(
                                                                 headers: { except: [:value, :extra] },
                                                                 remove_empty_values: false
                                                               ))
        data.each do |row|
          expect(row.keys).to match_array([:name])
          expect(row.keys).not_to include(:value, :extra)
        end
      end
    end

    # --- backwards compatibility: deprecated only_headers: / except_headers: still work ---

    it 'deprecated only_headers: still works (emits warning)' do
      expect do
        data = SmarterCSV.process("#{fixture_path}/basic.csv", base_options.merge(only_headers: [:first_name]))
        data.each { |row| expect(row.keys).to match_array([:first_name]) }
      end.to output(/DEPRECATION WARNING.*only_headers/).to_stderr
    end

    it 'deprecated except_headers: still works (emits warning)' do
      expect do
        data = SmarterCSV.process("#{fixture_path}/basic.csv", base_options.merge(except_headers: [:dogs]))
        data.each { |row| expect(row.keys).not_to include(:dogs) }
      end.to output(/DEPRECATION WARNING.*except_headers/).to_stderr
    end
  end
end
