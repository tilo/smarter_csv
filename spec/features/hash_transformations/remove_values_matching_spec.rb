# frozen_string_literal: true

fixture_path = 'spec/fixtures'

[true, false].each do |bool|
  describe ":remove_values_matching option with#{bool ? ' C-' : 'out '}acceleration" do
    it 'removes values' do
      options = {acceleration: bool, remove_zero_values: true, remove_empty_values: true, remove_values_matching: /^\d+$/}
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

    it 'removes values matching numeric values already converted to integers' do
      # When convert_values_to_numeric is true (default), numeric strings become integers/floats.
      # remove_values_matching should still match against the string representation.
      options = {acceleration: bool, convert_values_to_numeric: true, remove_values_matching: /\A0\z/}
      data = SmarterCSV.process("#{fixture_path}/basic.csv", options)

      data.each do |hash|
        # Numeric zero values (converted from "0") should be removed by matching "0"
        hash.each_value do |val|
          expect(val).not_to eq(0) if val.is_a?(Numeric)
        end
      end
    end
  end
end
