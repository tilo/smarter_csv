# frozen_string_literal: true

require 'spec_helper'

fixture_path = 'spec/fixtures'

describe 'silence missing keys' do
  let(:options) { { key_mapping: {THIS: :this, missing_key: :something} } }
  subject(:read_csv) { SmarterCSV.process("#{fixture_path}/silence_missing_keys.csv", options) }

  it 'prints warning message for missing keys by default' do
    expect(SmarterCSV).to receive(:puts)
    read_csv
  end

  it 'does not print warning message for missing keys when silenced' do
    options[:silence_missing_keys] = true
    expect(SmarterCSV).not_to receive(:puts)
    read_csv
  end

  it 'fetches the correct keys from the CSV file' do
    options[:silence_missing_keys] = true
    data = read_csv
    expect(data.size).to eq 1
    expect(data[0].keys).to eq %i[this that]
  end
end
