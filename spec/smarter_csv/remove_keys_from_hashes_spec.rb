# frozen_string_literal: true

require 'spec_helper'

fixture_path = 'spec/fixtures'

describe 'be_able_to' do
  it 'remove_values_matching' do
    options = {remove_zero_values: true, key_mapping: {first_name: :vorname, last_name: :nachname, fish: nil} }
    data = SmarterCSV.process("#{fixture_path}/basic.csv", options)
    expect(data.size).to eq 5

    data.each do |hash|
      hash.each_key do |key|
        expect(key.class).to eq Symbol # all the keys should be symbols

        expect(%i[vorname nachname dogs cats birds]).to include(key)
      end
      expect(hash.values).to_not include(0)

      expect(hash.size).to be <= 6
    end
  end
end
