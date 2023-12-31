# frozen_string_literal: true

require 'spec_helper'

fixture_path = 'spec/fixtures'

describe ':remove_zero_values option' do
  it 'removes zero values' do
    options = {remove_zero_values: true, remove_empty_values: true}
    data = SmarterCSV.process("#{fixture_path}/basic.csv", options)
    expect(data.size).to eq 5

    data.each do |hash|
      hash.each_key do |key|
        expect(key.class).to eq Symbol # all the keys should be symbols

        expect(%i[first_name last_name dogs cats birds fish]).to include(key)
      end

      expect(hash.values).not_to include(0)

      expect(hash.size).to be <= 6
    end
  end
end
