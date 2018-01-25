require 'spec_helper'

fixture_path = 'spec/fixtures'

describe 'test exceptions for invalid headers' do

  describe 'duplicate headers validation' do

    it 'raises error on duplicate headers by default' do
      expect {
        SmarterCSV.process("#{fixture_path}/duplicate_headers.csv")
      }.to raise_exception(SmarterCSV::DuplicateHeaders)
    end

    it 'raises error when v1 defaults are used' do
      options = { defaults: 'v1'}
      expect {
        SmarterCSV.process("#{fixture_path}/duplicate_headers.csv", options)
      }.to raise_exception(SmarterCSV::DuplicateHeaders)
    end

    it 'raises error when safe defaults are used' do
      options = { defaults: 'safe'}
      expect {
        SmarterCSV.process("#{fixture_path}/duplicate_headers.csv", options)
      }.to raise_exception(SmarterCSV::DuplicateHeaders)
    end

    it 'raises error when explicit validation is used' do
      options = { header_validations: [ :unique_headers ] }
      expect {
        SmarterCSV.process("#{fixture_path}/duplicate_headers.csv", options)
      }.to raise_exception(SmarterCSV::DuplicateHeaders)
    end

    it 'raises error on duplicate given headers' do
      expect {
        options = {user_provided_headers: [:a,:b,:c,:d,:a]}
        SmarterCSV.process("#{fixture_path}/duplicate_headers.csv", options)
      }.to raise_exception(SmarterCSV::DuplicateHeaders)
    end

    it 'raises error on duplicate mapped headers' do
      expect {
        # the mapping is right, but the underlying csv file is bad
        options = {
          header_transformations: [ key_mapping: {'email' => :a, 'firstname' => :b, 'lastname' => :c, 'manager_email' => :d, 'age' => :e, 'extra' => :not_used} ]
        }
        SmarterCSV.process("#{fixture_path}/duplicate_headers.csv", options)
      }.to raise_exception(SmarterCSV::DuplicateHeaders)
    end
  end


  describe 'required headers validation' do

    it 'does not raise an error if no required headers are given' do
      options = {header_validations: nil} # order does not matter
      data = SmarterCSV.process("#{fixture_path}/user_import.csv", options)
      data.size.should eq 2
    end

    it 'does not raise an error if no required headers are given' do
      options = {header_validations: []} # order does not matter
      data = SmarterCSV.process("#{fixture_path}/user_import.csv", options)
      data.size.should eq 2
    end

    it 'does not raise an error if the required headers are present' do
      options = {header_validations: [ required_headers: %i[lastname email firstname manager_email] ]} # order does not matter
      data = SmarterCSV.process("#{fixture_path}/user_import.csv", options)
      data.size.should eq 2
    end

    it 'raises an error if required header are missing' do
      expect {
        options = {header_validations: [ required_headers: %i[id lastname email employee_id firstname manager_email] ]} # order does not matter
        SmarterCSV.process("#{fixture_path}/user_import.csv", options)
      }.to raise_exception(SmarterCSV::MissingHeaders)
    end
  end
end
