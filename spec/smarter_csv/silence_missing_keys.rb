# frozen_string_literal: true

require 'spec_helper'

fixture_path = 'spec/fixtures'

describe 'be_able_to' do
  it 'throws_error_if_missing_keys_by_default' do
    options = {key_mapping: {THIS: :this, missing_key: :that}}
    expect { SmarterCSV.process("#{fixture_path}/silence_missing_keys.csv", options) }.to raise_error
  end

  it 'loads_csv_without_missing_keys_if_silence_missing_keys_is_set' do
    options = {silence_missing_keys: true, key_mapping: {THIS: :this, missing_key: :that}}
    data = SmarterCSV.process("#{fixture_path}/silence_missing_keys.csv", options)
    expect(data.size).to eq 1
    data.each do |item|
      item.each_key do |key|
        expect(key.class).to eq Symbol # all the keys should be symbols
        expect(%i[this THAT]).to include(key)
      end
    end
  end
end
