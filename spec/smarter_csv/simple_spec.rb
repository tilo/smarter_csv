# frozen_string_literal: true

require 'spec_helper'

fixture_path = 'spec/fixtures'


describe 'handling files with one column' do
  let(:options) { {} }
  subject(:data) { SmarterCSV.process(file, options) }

  context 'when simple file with header' do
    let(:file) { "#{fixture_path}/simple_with_header.csv" }

    xit 'loads the csv file without issues' do
      expect(data.size).to eq 4 # should not raise
    end
  end

  context 'when simple file without header' do
    let(:file) { "#{fixture_path}/simple_no_header.csv" }

    xit 'loads the csv file without issues' do
      expect(data.size).to eq 4 # should not raise
    end
  end
end
