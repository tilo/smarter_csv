# frozen_string_literal: true

require 'spec_helper'

fixture_path = 'spec/fixtures'

describe 'required_headers -> required_keys' do
  let(:options) { {} }
  subject(:data) { SmarterCSV.process("#{fixture_path}/required_headers.csv", options) }

  it 'loads the csv file without issues' do
    expect(data.size).to eq 3
    expect(data[0][:name]).to eq 'Bill'
  end

  describe 'with deprecated required_headers' do
    before do
      options[:key_mapping] = {name: :first_name}
    end

    it 'uses the attribute name after header transformation' do
      options[:required_headers] = [:first_name]
      expect(data.size).to eq 3
      expect(data[0][:first_name]).to eq 'Bill'
    end

    it 'raises an exception if the raw header name is used' do
      options[:required_headers] = [:name]
      expect{ data }.to raise_exception(SmarterCSV::MissingKeys)
    end

    it 'prints a deprecation warning when required_headers is used' do
      options[:required_headers] = [:first_name]
      expect(SmarterCSV).to receive(:puts).with(
        "DEPRECATION WARNING: please use 'required_keys' instead of 'required_headers'"
      )
      expect(SmarterCSV).to receive(:puts).with(
        "DEPRECATION WARNING: SmarterCSV #{SmarterCSV::VERSION} DEPRECATED OPTIONS: [:key_mapping, :required_headers]"
      )
      data
    end
  end

  describe 'with deprecated required_keys' do
    before do
      options[:key_mapping] = {name: :first_name}
    end

    it 'uses the attribute name after header transformation' do
      options[:required_keys] = [:first_name]
      expect(data.size).to eq 3
      expect(data[0][:first_name]).to eq 'Bill'
    end

    it 'raises an exception if the raw header name is used' do
      options[:required_keys] = [:name]
      expect{ data }.to raise_exception(SmarterCSV::MissingKeys)
    end

    it 'does not print a deprecation warning when required_keys is used' do
      options[:required_keys] = [:first_name]
      expect(SmarterCSV).to receive(:puts).with(
        "DEPRECATION WARNING: SmarterCSV #{SmarterCSV::VERSION} DEPRECATED OPTIONS: [:key_mapping, :required_keys]"
      )
      data
    end
  end
end
