# frozen_string_literal: true

fixture_path = 'spec/fixtures'

describe 'required_headers -> required_keys' do
  let(:options) { {} }
  let(:reader) { SmarterCSV::Reader.new(file, options) }
  let(:file) { "#{fixture_path}/required_headers.csv" }

  it 'loads the csv file without issues' do
    data = reader.process

    expect(data.size).to eq 3
    expect(data[0][:name]).to eq 'Bill'
  end

  describe 'with deprecated required_headers' do
    before do
      options[:key_mapping] = {name: :first_name}
    end

    it 'uses the attribute name after header transformation' do
      options[:required_headers] = [:first_name]
      data = reader.process

      expect(data.size).to eq 3
      expect(data[0][:first_name]).to eq 'Bill'
    end

    it 'raises an exception if the raw header name is used' do
      options[:required_headers] = [:name]

      expect{ reader.process }.to raise_exception(SmarterCSV::MissingKeys)
    end

    it 'prints a deprecation warning when required_headers is used' do
      options[:required_headers] = [:first_name]

      expect_any_instance_of(SmarterCSV::Options).to receive(:puts).with a_string_matching(/DEPRECATION WARNING/)
      reader.process
    end
  end

  describe 'with deprecated required_keys' do
    before do
      options[:key_mapping] = {name: :first_name}
    end

    it 'uses the attribute name after header transformation' do
      options[:required_keys] = [:first_name]
      data = reader.process

      expect(data.size).to eq 3
      expect(data[0][:first_name]).to eq 'Bill'
    end

    it 'raises an exception if the raw header name is used' do
      options[:required_keys] = [:name]

      expect{ reader.process }.to raise_exception(SmarterCSV::MissingKeys)
    end

    it 'does not print a deprecation warning when required_keys is used' do
      options[:required_keys] = [:first_name]
      expect(SmarterCSV).not_to receive(:puts).with a_string_matching(/DEPRECATION WARNING/)
      reader.process
    end
  end
end
