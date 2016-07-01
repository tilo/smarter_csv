require 'spec_helper'

fixture_path = 'spec/fixtures'

describe 'be_able_to' do
  let(:quoted_model_patten){ /\A[^\"]+\"[^\"]+\"\z/ }

  it 'loads_file_with_quoted_fields' do
    options = {}
    data = SmarterCSV.process("#{fixture_path}/quoted.csv", options)
    data.flatten.size.should == 4
    data[1][:model].should match quoted_model_patten
    data[1][:description].should be_nil
    data[2][:model].should match quoted_model_patten
    data[2][:description].should be_nil
  end

  it 'loads_file_with_quoted_fields' do
    options = {:force_simple_split => true}
    data = SmarterCSV.process("#{fixture_path}/quoted.csv", options)
    data.flatten.size.should == 4
    data[1][:model].should match quoted_model_patten
    data[1][:description].should be_nil
    data[2][:model].should match /\A[^\"]+\"[^\"]+\z/
    data[2][:description].should match /\A[^\"]+\"\z/
  end
end
