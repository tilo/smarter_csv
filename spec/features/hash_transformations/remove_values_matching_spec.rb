# frozen_string_literal: true

fixture_path = 'spec/fixtures'

describe ':remove_values_matching option' do
  it 'removes values' do
    options = {remove_zero_values: true, remove_empty_values: true, remove_values_matching: /^\d+$/}
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
end
