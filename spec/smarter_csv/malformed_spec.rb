require 'spec_helper'

fixture_path = 'spec/fixtures'

describe 'malformed_csv' do
  subject { -> { SmarterCSV.process(csv_path) } }

  context "malformed header" do
    let(:csv_path) { "#{fixture_path}/malformed_header.csv" }
    it { is_expected.to raise_error(CSV::MalformedCSVError) }
    it { is_expected.to raise_error(/Missing or stray quote in line 1/) }
    it { is_expected.to raise_error(/\[SmarterCSV: line 1\]/) }
  end

  context "malformed content" do
    let(:csv_path) { "#{fixture_path}/malformed.csv" }
    it { is_expected.to raise_error(CSV::MalformedCSVError) }
    it { is_expected.to raise_error(/Missing or stray quote in line 1/) }
    it { is_expected.to raise_error(/\[SmarterCSV: line 3\]/) }
  end
end
