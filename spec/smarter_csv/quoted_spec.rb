require 'spec_helper'

fixture_path = 'spec/fixtures'

describe 'be_able_to' do
  it 'loads_file_with_quoted_fields' do 
    options = {}
    data = SmarterCSV.process("#{fixture_path}/quoted.csv", options)
    data.flatten.size.should == 4
    data[1][:description].should be_nil
    data[2][:description].should be_nil
  end
end
