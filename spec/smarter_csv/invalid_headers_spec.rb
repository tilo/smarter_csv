# frozen_string_literal: true

require 'spec_helper'

fixture_path = 'spec/fixtures'

describe 'test exceptions for invalid headers' do
  it 'does not raise an error if no required headers are given' do
    options = {required_headers: nil} # order does not matter
    data = SmarterCSV.process("#{fixture_path}/user_import.csv", options)
    data.size.should eq 2
  end

  it 'does not raise an error if no required headers are given' do
    options = {required_headers: []} # order does not matter
    data = SmarterCSV.process("#{fixture_path}/user_import.csv", options)
    data.size.should eq 2
  end

  it 'does not raise an error if the required headers are present' do
    options = {required_headers: %i[lastname email firstname manager_email]} # order does not matter
    data = SmarterCSV.process("#{fixture_path}/user_import.csv", options)
    data.size.should eq 2
  end

  it 'raises an error if a required header is missing' do
    expect do
      options = {required_headers: %i[lastname email employee_id firstname manager_email]} # order does not matter
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
end
