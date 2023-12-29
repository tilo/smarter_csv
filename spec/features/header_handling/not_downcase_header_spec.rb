# frozen_string_literal: true

require 'spec_helper'

fixture_path = 'spec/fixtures'

describe ':downcase_header option' do
  it 'not_downcase_headers' do
    options = {downcase_header: false}
    data = SmarterCSV.process("#{fixture_path}/basic.csv", options)
    expect(data.size).to eq 5

    data.each do |h|
      h.each_key do |key|
        expect(key.class).to eq Symbol # all the keys should be symbols

        expect(%i[First_Name Last_Name Dogs Cats Birds Fish]).to include(key)
      end

      expect(h.size).to be <= 6
    end
  end
end
