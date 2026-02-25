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
end
