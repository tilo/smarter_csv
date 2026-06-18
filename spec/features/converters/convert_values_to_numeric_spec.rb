# frozen_string_literal: true

fixture_path = 'spec/fixtures'

describe 'numeric conversion of values' do
  [true, false].each do |acceleration|
    context "acceleration: #{acceleration}" do
      it 'occurs by default' do
        data = SmarterCSV.process("#{fixture_path}/numeric.csv", acceleration: acceleration)
        expect(data.size).to eq 3
        data.each do |hash|
          expect(hash[:wealth]).to be_a_kind_of(Numeric) unless hash[:wealth].nil?
          expect(hash[:reference]).to be_a_kind_of(Numeric) unless hash[:reference].nil?
        end
      end

      it 'can be prevented for all values' do
        data = SmarterCSV.process("#{fixture_path}/numeric.csv",
                                  acceleration: acceleration,
                                  convert_values_to_numeric: false)
        data.each do |hash|
          expect(hash[:wealth]).to be_a_kind_of(String) unless hash[:wealth].nil?
          expect(hash[:reference]).to be_a_kind_of(String) unless hash[:reference].nil?
        end
      end

      it 'can be prevented for some keys' do
        data = SmarterCSV.process("#{fixture_path}/numeric.csv",
                                  acceleration: acceleration,
                                  convert_values_to_numeric: { except: [:reference, :zip_code] })
        data.each do |hash|
          expect(hash[:wealth]).to be_a_kind_of(Numeric) unless hash[:wealth].nil?
          expect(hash[:reference]).to be_a_kind_of(String) unless hash[:reference].nil?
          expect(hash[:zip_code]).to be_a_kind_of(String) unless hash[:zip_code].nil?
        end
      end

      it 'can occur only for some keys' do
        data = SmarterCSV.process("#{fixture_path}/numeric.csv",
                                  acceleration: acceleration,
                                  convert_values_to_numeric: { only: :wealth })
        data.each do |hash|
          expect(hash[:wealth]).to be_a_kind_of(Numeric) unless hash[:wealth].nil?
          expect(hash[:reference]).to be_a_kind_of(String) unless hash[:reference].nil?
        end
      end
    end

    # Characterization of numeric-conversion behavior on edge inputs.
    # Base-10 conversion (leading zeros do NOT mean octal); radix prefixes and underscores are
    # NOT converted. As of 1.18.0 the C and Ruby paths are aligned: scientific notation (with or
    # without a dot) converts on both paths, and bare-dot forms (".5", "3.") stay String on both
    # (the shared grammar requires an integer part and, if a dot is present, a fraction digit).
    describe 'numeric conversion — edge-input characterization' do
      require 'stringio'

      def converted(value, acceleration)
        SmarterCSV.process(StringIO.new("h\n#{value}\n"), col_sep: ',', acceleration: acceleration).first[:h]
      end

      # Both paths agree on these. (`eql` is type-strict: distinguishes 10 from 10.0.)
      [
        ['010',    10],            # leading zeros → decimal, NOT octal 8
        ['007',    7],
        ['0123',   123],           # NOT octal 0o123 (= 83)
        ['-0123',  -123],          # signed + leading zeros
        ['+007',   7],
        ['42',     42],
        ['+42',    42],
        ['-42',    -42],
        ['3.14',   3.14],
        ['-3.14',  -3.14],
        ['0',      0],             # plain zero (remove_zero_values is off here, so it's kept)
        ['+0',     0],             # signed zeros: Integer 0 carries no sign
        ['-0',     0],
        ['00',     0],
        ['000',    0],
        ['0.0',    0.0],
        ['+0.0',   0.0],
        ['-0.0',   -0.0],          # Float keeps negative zero
        ['+0.00',  0.0],
        ['-0.00',  -0.0],
        ['0x1F',   '0x1F'],        # radix prefixes are not honored
        ['0xFF',   '0xFF'],
        ['0b101',  '0b101'],
        ['0o17',   '0o17'],
        ['1e3',    1000.0],        # scientific notation (no dot) now converts → Float
        ['1E3',    1000.0],
        ['1_000',  '1_000'],       # underscores — not converted
        ['1.2.3',  '1.2.3'],       # not a number
        ['-',      '-'],           # lone sign — not a number
        ['+',      '+'],
      ].each do |value, expected|
        it "converts #{value.inspect} to #{expected.inspect} (acceleration: #{acceleration})" do
          expect(converted(value, acceleration)).to eql expected
        end
      end

      # CONVERGED in 1.18.0 (these used to differ between the C and Ruby paths).
      # The shared grammar requires an integer part, and a fraction digit when a dot is present,
      # so bare-dot forms stay String on BOTH paths; scientific-with-dot converts on BOTH.
      [
        ['.5',     '.5'],            # no integer part → not a number
        ['3.',     '3.'],            # dot with no fraction digit → not a number
        ['1.5e3',  1500.0],          # scientific with a dot → Float (both paths)
        ['1.0e10', 10_000_000_000.0],
      ].each do |value, expected|
        it "converts #{value.inspect} to #{expected.inspect} (acceleration: #{acceleration})" do
          expect(converted(value, acceleration)).to eql expected
        end
      end
    end
  end
end
