# frozen_string_literal: true

fixture_path = 'spec/fixtures'

[true, false].each do |bool|
  describe ":nil_values_matching option with#{bool ? ' C-' : 'out '}acceleration" do
    context "with remove_empty_values: true (default) — net behavior: matching values removed" do
      it 'removes key-value pairs whose value matches the regex' do
        options = { acceleration: bool, remove_zero_values: true, remove_empty_values: true, nil_values_matching: /^\d+$/ }
        data = SmarterCSV.process("#{fixture_path}/basic.csv", options)
        expect(data.size).to eq 5

        data.each do |hash|
          hash.each_key do |key|
            expect(key.class).to eq Symbol # all the keys should be symbols
            expect(%i[first_name last_name]).to include(key)
          end

          hash.each_value do |val|
            expect(val.class).to eq String # all the values should be strings
          end

          expect(hash.values).not_to include(0)
          expect(hash.size).to be <= 6
        end
      end

      it 'matches against the string representation of already-converted numeric values' do
        # When convert_values_to_numeric is true (default), numeric strings become integers/floats.
        # nil_values_matching matches against the string representation.
        options = { acceleration: bool, convert_values_to_numeric: true, nil_values_matching: /\A0\z/ }
        data = SmarterCSV.process("#{fixture_path}/basic.csv", options)

        data.each do |hash|
          hash.each_value do |val|
            expect(val).not_to eq(0) if val.is_a?(Numeric)
          end
        end
      end
    end

    context "with remove_empty_values: false — matching values set to nil, key retained" do
      it 'sets matching values to nil and keeps the key' do
        csv = "name,status\nAlice,NULL\nBob,active\n"
        options = { acceleration: bool, nil_values_matching: /\ANULL\z/, remove_empty_values: false }
        data = SmarterCSV.process(StringIO.new(csv), options)

        alice = data.find { |r| r[:name] == 'Alice' }
        expect(alice).not_to be_nil
        expect(alice.key?(:status)).to be true   # key retained
        expect(alice[:status]).to be_nil         # value set to nil

        bob = data.find { |r| r[:name] == 'Bob' }
        expect(bob[:status]).to eq 'active'      # non-matching value unchanged
      end

      it 'handles common spreadsheet sentinel values (NaN, #VALUE!)' do
        csv = "col1,col2\nNaN,good\n#VALUE!,also good\n"
        options = { acceleration: bool, nil_values_matching: /\A(NaN|#VALUE!)\z/, remove_empty_values: false }
        data = SmarterCSV.process(StringIO.new(csv), options)

        data.each do |row|
          expect(row.key?(:col1)).to be true
          expect(row[:col1]).to be_nil
        end
      end
    end
  end

  describe ":remove_values_matching (deprecated) with#{bool ? ' C-' : 'out '}acceleration" do
    it 'still works but emits a deprecation warning' do
      options = { acceleration: bool, remove_values_matching: /^\d+$/ }
      expect do
        data = SmarterCSV.process("#{fixture_path}/basic.csv", options)
        expect(data).not_to be_empty
      end.to output(/DEPRECATION WARNING.*remove_values_matching/).to_stderr
    end

    it 'behaves identically to nil_values_matching with the default remove_empty_values: true' do
      csv = "name,code\nAlice,123\nBob,abc\n"
      old_options = { acceleration: bool, remove_values_matching: /\A\d+\z/ }
      new_options = { acceleration: bool, nil_values_matching:    /\A\d+\z/ }

      old_data = nil
      expect { old_data = SmarterCSV.process(StringIO.new(csv), old_options) }.to output(/DEPRECATION/).to_stderr
      new_data = SmarterCSV.process(StringIO.new(csv), new_options)

      expect(new_data).to eq(old_data)
    end
  end

  # The pattern is written against what's in the file, so it must be matched against the RAW
  # string value of the field — before numeric conversion — on both paths. "007" must be
  # matched as "007", not as the converted 7.
  describe ":nil_values_matching applies to the raw string value with#{bool ? ' C-' : 'out '}acceleration" do
    it 'removes the key when the raw string matches (remove_empty_values: true, default)' do
      result = SmarterCSV.process(StringIO.new("a,b\n007,x\n"), nil_values_matching: /\A007\z/, acceleration: bool)
      expect(result).to eq [{ b: 'x' }]
    end

    it 'sets the value to nil and keeps the key (remove_empty_values: false)' do
      result = SmarterCSV.process(StringIO.new("a,b\n007,x\n"), nil_values_matching: /\A007\z/, remove_empty_values: false, acceleration: bool)
      expect(result).to eq [{ a: nil, b: 'x' }]
    end
  end

  # Setting nil_values_matching must NOT switch off the other value transformations:
  # non-matching values still get numeric conversion, zero-removal, and value_converters
  # (which see the CONVERTED value) — in the same order as without the option.
  describe ":nil_values_matching composes with the other transforms with#{bool ? ' C-' : 'out '}acceleration" do
    it 'still converts non-matching values to numeric' do
      result = SmarterCSV.process(StringIO.new("a,b\n42,3.5\n"), nil_values_matching: /\ANULL\z/, acceleration: bool)
      expect(result).to eq [{ a: 42, b: 3.5 }]
      expect(result.first[:a]).to be_an(Integer)
      expect(result.first[:b]).to be_a(Float)
    end

    it 'still removes zero values (remove_zero_values: true)' do
      result = SmarterCSV.process(StringIO.new("a,b\n0,x\n"), nil_values_matching: /\ANULL\z/, remove_zero_values: true, acceleration: bool)
      expect(result).to eq [{ b: 'x' }]
    end

    it 'value_converters receive the numerically converted value' do
      result = SmarterCSV.process(StringIO.new("a,b\n7,x\n"), nil_values_matching: /\Azzz\z/, value_converters: { a: ->(v) { v.class.to_s } }, acceleration: bool)
      expect(result).to eq [{ a: 'Integer', b: 'x' }]
    end
  end
end
