# frozen_string_literal: true

fixture_path = 'spec/fixtures'

describe 'key_mapping' do
  describe 'exception for missing keys / header names' do
    let(:options) { {} }
    subject(:data) { SmarterCSV.process("#{fixture_path}/basic.csv", options) }

    it 'complains about the original header name when source of key_mapping is missing' do
      options[:key_mapping] = {missing_key: :something_new}
      expect(SmarterCSV).not_to receive(:puts).with a_string_matching(/WARNING.*missing_key/)
      expect { data }.to raise_exception(
        SmarterCSV::KeyMappingError, "ERROR: can not map headers: missing_key"
      )
    end
  end

  context 'with empty key_mapping' do
    let(:options) { {key_mapping: {}} }

    it 'raises an exception if the key_mapping is empty' do
      expect do
        SmarterCSV.process("#{fixture_path}/basic.csv", options)
      end.to raise_exception(
        SmarterCSV::IncorrectOption,
        /ERROR: incorrect format for key_mapping! Expecting hash with from -> to mappings/
      )
    end
  end

  context 'with incorrect key_mapping' do
    let(:options) { {key_mapping: []} }

    it 'raises an exception if the key_mapping is of incorrect type' do
      expect do
        SmarterCSV.process("#{fixture_path}/basic.csv", options)
      end.to raise_exception(
        SmarterCSV::IncorrectOption,
        /ERROR: incorrect format for key_mapping! Expecting hash with from -> to mappings/
      )
    end
  end

  it 'remove_values_matching' do
    options = {remove_zero_values: true, key_mapping: {first_name: :vorname, last_name: :nachname} }
    data = SmarterCSV.process("#{fixture_path}/basic.csv", options)
    expect(data.size).to eq 5

    data.each do |hash|
      hash.each_key do |key|
        expect(key.class).to eq Symbol # all the keys should be symbols

        expect(%i[vorname nachname dogs cats birds fish]).to include(key)
      end

      expect(hash.values).not_to include(0)

      expect(hash.size).to be <= 6
    end
  end

  describe 'when keep_original_headers' do
    it 'without key mapping' do
      options = {keep_original_headers: true}
      data = SmarterCSV.process("#{fixture_path}/key_mapping.csv", options)
      expect(data.size).to eq 1
      expect(data.first.keys).to eq %w[THIS THAT other]
    end

    it 'sets key_mapping to a symbol' do
      options = {keep_original_headers: true, key_mapping: {'other' => :other}}
      data = SmarterCSV.process("#{fixture_path}/key_mapping.csv", options)
      expect(data.size).to eq 1
      expect(data.first.keys).to eq ['THIS', 'THAT', :other]
    end

    # this previously would set the key to a symbol :OTHER, which was a bug!
    it 'sets key_mapping to a string' do
      options = {keep_original_headers: true, key_mapping: {'other' => 'OTHER'}}
      data = SmarterCSV.process("#{fixture_path}/key_mapping.csv", options)
      expect(data.size).to eq 1
      expect(data.first.keys).to eq %w[THIS THAT OTHER]
    end

    # users now have to explicitly set this to a symbol, or change the expected keys to be strings.
    it 'sets key_mapping to a symbol' do
      options = {keep_original_headers: true, key_mapping: {'other' => :OTHER}}
      data = SmarterCSV.process("#{fixture_path}/key_mapping.csv", options)
      expect(data.size).to eq 1
      expect(data.first.keys).to eq ['THIS', 'THAT', :OTHER]
    end
  end
end
