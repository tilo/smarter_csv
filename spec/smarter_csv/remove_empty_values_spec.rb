require 'spec_helper'

fixture_path = 'spec/fixtures'

describe 'be_able_to' do
  it 'remove_empty_values' do 
    options = {:row_sep => :auto, :remove_empty_values => true}
    data = SmarterCSV.process("#{fixture_path}/empty.csv", options)
    data.size.should == 1
    data[0].keys.should == [:not_empty_1, :not_empty_2, :not_empty_3]
  end

end
