require 'spec_helper'

fixture_path = 'spec/fixtures'

describe 'be_able_to' do
  it 'loads_file_with_different_column_separator' do 
    options = {:col_sep => ';'}
    data = SmarterCSV.process("#{fixture_path}/separator.csv", options)
    data.flatten.size.should == 3
  end
end
