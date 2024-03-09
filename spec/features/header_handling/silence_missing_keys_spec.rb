# frozen_string_literal: true

fixture_path = 'spec/fixtures'

describe 'silence missing keys' do
  # "THIS" is automatically mapped to "this" -> no need to do this mapping here
  let(:options) { { key_mapping: {THIS: :this, missing_key: :something} } }
  subject(:read_csv) { SmarterCSV.process("#{fixture_path}/silence_missing_keys.csv", options) }

  it 'prints warning message for missing keys by default' do
    expect(SmarterCSV).not_to receive(:puts)
    expect{ read_csv }.to raise_exception(
      SmarterCSV::KeyMappingError, "ERROR: can not map headers: THIS, missing_key"
    )
  end

  it 'maps the keys from the CSV file correctly' do
    options[:silence_missing_keys] = true
    expect(SmarterCSV).not_to receive(:puts)
    data = SmarterCSV.process("#{fixture_path}/silence_missing_keys.csv", options)
    expect(data.size).to eq 1
    expect(data[0].keys).to eq %i[this that]
  end
end
