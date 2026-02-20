# frozen_string_literal: true

# Tests for Phase 1: hash transformations moved into C extension.
# Each scenario runs with both acceleration on (C path) and off (Ruby fallback)
# to verify identical results.

fixture_path = 'spec/fixtures'

describe 'C-accelerated hash transformations' do
  [true, false].each do |acceleration|
    context "with acceleration #{acceleration}" do
      # --- Numeric conversion ---

      describe 'numeric conversion' do
        it 'converts integers and floats by default' do
          data = SmarterCSV.process("#{fixture_path}/transformations.csv", acceleration: acceleration)

          data.each do |hash|
            expect(hash[:int_val]).to be_a_kind_of(Integer) unless hash[:int_val].nil?
            expect(hash[:float_val]).to be_a_kind_of(Float) unless hash[:float_val].nil?
          end

          expect(data[0][:int_val]).to eq 42
          expect(data[0][:float_val]).to eq 3.14
          expect(data[1][:int_val]).to eq 0
          expect(data[1][:float_val]).to eq 0.0
        end

        it 'handles signed numbers' do
          data = SmarterCSV.process("#{fixture_path}/transformations.csv", acceleration: acceleration)

          expect(data[0][:signed_neg]).to eq(-7)
          expect(data[0][:signed_pos]).to eq 100
          expect(data[2][:signed_neg]).to eq(-99)
          expect(data[2][:signed_pos]).to eq 42
        end

        it 'handles very large integers (Bignum)' do
          data = SmarterCSV.process("#{fixture_path}/transformations.csv", acceleration: acceleration)

          expect(data[0][:big_number]).to eq 99999999999999999999
          expect(data[0][:big_number]).to be_a_kind_of(Integer)
        end

        it 'leaves non-numeric strings as strings' do
          data = SmarterCSV.process("#{fixture_path}/transformations.csv", acceleration: acceleration)

          expect(data[0][:not_numeric]).to eq 'hello'
          expect(data[1][:not_numeric]).to eq 'world'
          expect(data[2][:not_numeric]).to eq '12abc'
        end

        it 'does not convert when convert_values_to_numeric is false' do
          data = SmarterCSV.process("#{fixture_path}/transformations.csv",
                                   acceleration: acceleration, convert_values_to_numeric: false)

          data.each do |hash|
            expect(hash[:int_val]).to be_a_kind_of(String) unless hash[:int_val].nil?
            expect(hash[:float_val]).to be_a_kind_of(String) unless hash[:float_val].nil?
          end
        end

        it 'respects only: option for selective conversion' do
          data = SmarterCSV.process("#{fixture_path}/transformations.csv",
                                   acceleration: acceleration,
                                   convert_values_to_numeric: { only: :int_val })

          expect(data[0][:int_val]).to eq 42
          expect(data[0][:float_val]).to eq '3.14'
          expect(data[0][:not_numeric]).to eq 'hello'
        end

        it 'respects except: option for selective conversion' do
          data = SmarterCSV.process("#{fixture_path}/transformations.csv",
                                   acceleration: acceleration,
                                   convert_values_to_numeric: { except: [:not_numeric, :name] })

          expect(data[0][:int_val]).to eq 42
          expect(data[0][:float_val]).to eq 3.14
          expect(data[0][:not_numeric]).to eq 'hello'
        end
      end

      # --- Remove zero values ---

      describe 'remove_zero_values' do
        it 'removes string zeros independently of numeric conversion' do
          # With numeric conversion OFF, zero strings should still be removed
          data = SmarterCSV.process("#{fixture_path}/transformations.csv",
                                   acceleration: acceleration,
                                   convert_values_to_numeric: false,
                                   remove_zero_values: true,
                                   remove_empty_values: true)

          data.each do |hash|
            # No values should be "0", "00", "0.0", "00.00", "000.000" etc.
            hash.each_value do |v|
              expect(v).not_to match(/\A0+(?:\.0+)?\z/) if v.is_a?(String)
            end
          end
        end

        it 'removes numeric zeros when conversion is enabled' do
          data = SmarterCSV.process("#{fixture_path}/basic.csv",
                                   acceleration: acceleration,
                                   remove_zero_values: true,
                                   remove_empty_values: true)

          data.each do |hash|
            expect(hash.values).not_to include(0)
            expect(hash.values).not_to include(0.0)
          end
        end

        it 'removes various zero string patterns' do
          data = SmarterCSV.process("#{fixture_path}/transformations.csv",
                                   acceleration: acceleration,
                                   convert_values_to_numeric: false,
                                   remove_zero_values: true,
                                   remove_empty_values: true)

          # Row 1 (Bob): zero_int="00", zero_float="00.00"
          bob = data[1]
          expect(bob).not_to have_key(:zero_int)
          expect(bob).not_to have_key(:zero_float)

          # Row 2 (Charlie): zero_int="000", zero_float="000.000"
          charlie = data[2]
          expect(charlie).not_to have_key(:zero_int)
          expect(charlie).not_to have_key(:zero_float)
        end
      end

      # --- Remove empty values ---

      describe 'remove_empty_values' do
        it 'removes blank and whitespace-only fields' do
          data = SmarterCSV.process("#{fixture_path}/transformations.csv",
                                   acceleration: acceleration,
                                   remove_empty_values: true)

          data.each do |hash|
            expect(hash).not_to have_key(:blank_field)
            expect(hash).not_to have_key(:whitespace_only)
          end
        end

        it 'keeps empty fields when remove_empty_values is false' do
          data = SmarterCSV.process("#{fixture_path}/transformations.csv",
                                   acceleration: acceleration,
                                   remove_empty_values: false,
                                   convert_values_to_numeric: false)

          # All rows should have all keys present
          expect(data[0]).to have_key(:blank_field)
        end
      end

      # --- Remove empty hashes ---

      describe 'remove_empty_hashes' do
        it 'skips all-blank rows' do
          data = SmarterCSV.process("#{fixture_path}/basic.csv",
                                   acceleration: acceleration,
                                   remove_empty_hashes: true,
                                   remove_empty_values: true)

          # basic.csv has 2 all-blank rows out of 7 data rows
          expect(data.size).to eq 5
        end

        it 'skips rows where all values are filtered out' do
          data = SmarterCSV.process("#{fixture_path}/basic.csv",
                                   acceleration: acceleration,
                                   remove_empty_hashes: true,
                                   remove_empty_values: true,
                                   remove_zero_values: true)

          # Row "Miles,O'Brian,0,0,0,21" has zeros for dogs/cats/birds but fish=21
          # All-blank rows are removed, but Miles row should remain (has name + fish)
          expect(data.size).to eq 5
          miles = data.find { |h| h[:first_name] == "Miles" }
          expect(miles).not_to be_nil
          expect(miles[:fish]).to eq 21
        end
      end

      # --- Combination of all options ---

      describe 'combined transformations' do
        it 'applies all transformations together' do
          data = SmarterCSV.process("#{fixture_path}/transformations.csv",
                                   acceleration: acceleration,
                                   remove_empty_values: true,
                                   remove_zero_values: true)

          alice = data[0]
          expect(alice[:name]).to eq 'Alice'
          expect(alice[:int_val]).to eq 42
          expect(alice[:float_val]).to eq 3.14
          expect(alice).not_to have_key(:zero_int)       # "0" removed
          expect(alice).not_to have_key(:zero_float)      # "0.0" removed
          expect(alice).not_to have_key(:blank_field)     # empty removed
          expect(alice).not_to have_key(:whitespace_only) # whitespace removed
          expect(alice[:signed_neg]).to eq(-7)
          expect(alice[:signed_pos]).to eq 100
          expect(alice[:not_numeric]).to eq 'hello'
        end
      end

      # --- C and Ruby produce identical results ---

      describe 'C/Ruby parity' do
        it 'produces identical results for all option combinations' do
          option_sets = [
            {},
            { remove_empty_values: true },
            { remove_zero_values: true, remove_empty_values: true },
            { convert_values_to_numeric: false },
            { convert_values_to_numeric: false, remove_zero_values: true, remove_empty_values: true },
            { convert_values_to_numeric: { only: :int_val }, remove_empty_values: true },
            { convert_values_to_numeric: { except: [:name, :not_numeric] }, remove_empty_values: true },
          ]

          option_sets.each do |opts|
            c_data = SmarterCSV.process("#{fixture_path}/transformations.csv", opts.merge(acceleration: true))
            ruby_data = SmarterCSV.process("#{fixture_path}/transformations.csv", opts.merge(acceleration: false))

            expect(c_data).to eq(ruby_data), "Mismatch with options: #{opts.inspect}\n  C:    #{c_data.inspect}\n  Ruby: #{ruby_data.inspect}"
          end
        end
      end
    end
  end
end
