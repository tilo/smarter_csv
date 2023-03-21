# frozen_string_literal: true

require 'spec_helper'

fixture_path = 'spec/fixtures'


describe 'handling files with one column' do
  let(:options) { {} }
  subject(:data) { SmarterCSV.process(file, options) }

  context 'when simple file with header' do
    let(:file) { "#{fixture_path}/simple_with_header.csv" }

    it 'loads the csv file without issues' do
      expect(data.size).to eq 4 # should not raise
    end
  end

  context 'when simple file without header' do
    let(:file) { "#{fixture_path}/simple_no_header.csv" }

    it 'loads the csv file without issues' do
      options[:headers_in_file] = false
      options[:user_provided_headers] = ['this']
      expect(data.size).to eq 4 # should not raise
    end
  end

  context 'when simple file with header and UTF-8 chars' do
    let(:file) { "#{fixture_path}/simple_with_header_utf8.csv" }

    it 'loads the csv file without issues' do
      expect{ data }.to raise_exception(SmarterCSV::NoColSepDetected)
    end
  end
end
