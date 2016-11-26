require 'spec_helper'

fixture_path = 'spec/fixtures'

describe 'process files with invalid characters' do
  it 'replaces the characters' do
    data = SmarterCSV.process("#{fixture_path}/invalid.csv", {})
    data.size.should == 2
    data[1][:first_name].should == "Ch�telat"
  end
end

