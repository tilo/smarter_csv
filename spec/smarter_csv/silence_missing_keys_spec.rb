# frozen_string_literal: true

require 'spec_helper'

fixture_path = 'spec/fixtures'

describe 'silence missing keys' do
  let(:options) { { key_mapping: {THIS: :this, missing_key: :something} } }

  it 'prints warning message for missing keys by default' do
    expect(SmarterCSV).to receive(:puts)
    SmarterCSV.process("#{fixture_path}/silence_missing_keys.csv", options)
  end

  it 'does not print warning message for missing keys when silenced' do
    options[:silence_missing_keys] = true
    expect(SmarterCSV).not_to receive(:puts)
    SmarterCSV.process("#{fixture_path}/silence_missing_keys.csv", options)
  end

  it 'fetches the correct keys from the CSV file' do
    options[:silence_missing_keys] = true
    expect(SmarterCSV).not_to receive(:puts)
    data = SmarterCSV.process("#{fixture_path}/silence_missing_keys.csv", options)
    expect(data.size).to eq 1
    expect(data[0].keys).to eq [:this, :that]
  end
end
