# frozen_string_literal: true

require 'spec_helper'

fixture_path = 'spec/fixtures'

describe ':keep_original_headers option' do
  it 'not_downcase_headers' do
    options = {keep_original_headers: true}
    data = SmarterCSV.process("#{fixture_path}/basic.csv", options)
    expect(data.size).to eq 5

    data.each do |hash|
      hash.each_key do |key|
        expect(key.class).to eq String # all the keys should be string

        expect(['First Name', 'Last Name', 'Dogs', 'Cats', 'Birds', 'Fish']).to include(key)
      end

      expect(hash.size).to be <= 6
    end
  end
end
