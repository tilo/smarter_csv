require 'spec_helper'

fixture_path = 'spec/fixtures'

describe 'be_able_to' do

  it 'loads_file_with_quoted_fields' do
    options = {}
    data = SmarterCSV.process("#{fixture_path}/quoted.csv", options)
    data.flatten.size.should == 4
    data[1][:model].should eq 'Venture "Extended Edition"'
    data[1][:description].should be_nil
    data[2][:model].should eq 'Venture "Extended Edition, Very Large"'
    data[2][:description].should be_nil
    data.each do |h|
      h[:year].class.should eq Fixnum
      h[:make].should_not be_nil
      h[:model].should_not be_nil
      h[:price].class.should eq Float
    end
  end

end
