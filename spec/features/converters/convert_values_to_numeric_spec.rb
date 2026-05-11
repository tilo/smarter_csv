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
  end
end

# Characterization of CURRENT numeric-conversion behavior on edge inputs.
# Most of these are the intended contract — base-10 conversion (so leading zeros do NOT mean
# octal), and radix prefixes / underscores / scientific notation are NOT converted. A few
# bare-dot and scientific-with-dot forms differ between the C and Ruby paths today; those are
# pinned here per path. See TO_DO.md ("Numeric conversion: align the Ruby fallback path with
# the C path") — when that lands, the Ruby-path expectations in the second block below change.
describe 'numeric conversion — edge-input characterization' do
  require 'stringio'

  def converted(value, accel)
    SmarterCSV.process(StringIO.new("h\n#{value}\n"), col_sep: ',', acceleration: accel).first[:h]
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
    ['1e3',    '1e3'],         # scientific notation without a '.' — not converted
    ['1E3',    '1E3'],
    ['1_000',  '1_000'],       # underscores — not converted
    ['1.2.3',  '1.2.3'],       # not a number
    ['-',      '-'],           # lone sign — not a number
    ['+',      '+'],
  ].each do |value, expected|
    [true, false].each do |accel|
      it "converts #{value.inspect} to #{expected.inspect} (acceleration: #{accel})" do
        expect(converted(value, accel)).to eql expected
      end
    end
  end

  # The C path (strtod) accepts bare-dot and scientific-with-dot forms; the Ruby fallback's
  # \A[+-]?\d+(?:\.\d+)?\z regex does not — so these diverge today.
  [
    ['.5',     0.5,              '.5'],
    ['3.',     3.0,              '3.'],
    ['1.5e3',  1500.0,           '1.5e3'],
    ['1.0e10', 10_000_000_000.0, '1.0e10'],
  ].each do |value, c_expected, rb_expected|
    [true, false].each do |accel|
      expected = accel ? c_expected : rb_expected
      it "converts #{value.inspect} to #{expected.inspect} on the #{accel ? 'C' : 'Ruby'} path (characterization — see TO_DO.md)" do
        expect(converted(value, accel)).to eql expected
      end
    end
  end
end
