require 'spec_helper'

fixture_path = 'spec/fixtures'

describe 'malformed_csv' do
  subject { lambda { SmarterCSV.process(csv_path) } }

  context "malformed header" do
    let(:csv_path) { "#{fixture_path}/malformed_header.csv" }
    it { should raise_error(CSV::MalformedCSVError) }
  end

  context "malformed content" do
    let(:csv_path) { "#{fixture_path}/malformed.csv" }
    it { should raise_error(CSV::MalformedCSVError) }
  end
end
