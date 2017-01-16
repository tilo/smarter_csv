require 'spec_helper'

fixture_path = 'spec/fixtures'

describe 'be_able_to' do

  subject { lambda { SmarterCSV.process(csv_path, {:multiline  => false}) } }

  context "it breaks on malformed content if multiline was not specified" do
    let(:csv_path) { "#{fixture_path}/empty.csv" }
    it { should raise_error(SmarterCSV::MalformedCSVError) }
  end

  it 'remove_empty_values' do
    options = {:row_sep => :auto, :remove_empty_values => true, :multiline => true}
    data = SmarterCSV.process("#{fixture_path}/empty.csv", options)
    data.size.should == 1
    data[0].keys.should == [:not_empty_1, :not_empty_2, :not_empty_3]
  end

end
