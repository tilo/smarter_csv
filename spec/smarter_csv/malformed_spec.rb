require 'spec_helper'

fixture_path = 'spec/fixtures'

describe 'malformed_csv' do
  context "malformed header" do
    let(:csv_path) { "#{fixture_path}/malformed_header.csv" }

    it 'raises exception' do
      expect{ SmarterCSV.process(csv_path) }.to raise_error(CSV::MalformedCSVError, anything)
    end
  end

  context "malformed content" do
    let(:csv_path) { "#{fixture_path}/malformed.csv" }

    it 'raises exception' do
      expect{ SmarterCSV.process(csv_path) }.to raise_error(CSV::MalformedCSVError, anything)
    end
  end
end
