# frozen_string_literal: true

require 'spec_helper'

fixture_path = 'spec/fixtures'

describe 'test exceptions for invalid headers' do
  it 'does not raise an error if no required headers are given' do
    options = {required_keys: nil} # order does not matter
    data = SmarterCSV.process("#{fixture_path}/user_import.csv", options)
    expect(data.size).to eq 2
  end

  it 'does not raise an error if no required headers are given' do
    options = {required_keys: []} # order does not matter
    data = SmarterCSV.process("#{fixture_path}/user_import.csv", options)
    expect(data.size).to eq 2
  end

  it 'does not raise an error if the required headers are present' do
    options = {required_keys: %i[lastname email firstname manager_email]} # order does not matter
    data = SmarterCSV.process("#{fixture_path}/user_import.csv", options)
    expect(data.size).to eq 2
  end

  it 'raises an error if a required header is missing' do
    expect do
      options = {required_keys: %i[lastname email employee_id firstname manager_email]} # order does not matter
      SmarterCSV.process("#{fixture_path}/user_import.csv", options)
    end.to raise_exception(SmarterCSV::MissingHeaders)
  end

  it 'does not raise error on missing mapped headers and includes missing headers in message' do
    # :age does not exist in the CSV header
    options = {key_mapping: {email: :a, firstname: :b, lastname: :c, manager_email: :d, age: :e} }
    expect do
      SmarterCSV.process("#{fixture_path}/user_import.csv", options)
    end.not_to raise_exception
  end


  # TO BE FIXED:
  #
  # this raises:  SmarterCSV::MissingHeaders: RROR: missing attributes: middle_name
  # but instead, the printed WARNING message for missing_keys should raise KeyMappingError
  #
  describe 'exception for missing keys / header names' do
    let(:options) do
      {
        required_keys: [:middle_name],
        key_mapping: { missing_key: :middle_name},
      }
    end
    subject(:data) { SmarterCSV.process("#{fixture_path}/user_import.csv", options) }

    # slated for version 1.9.0
    xit 'complains about the original header name when source of key_mapping is missing' do
      expect(SmarterCSV).to receive(:puts).with a_string_matching(/WARNING.*missing_key/)
      expect{ data }.to raise_exception(SmarterCSV::KeyMappingError)
    end
  end
end
