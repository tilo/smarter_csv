require 'spec_helper'

fixture_path = 'spec/fixtures'

describe 'be_able_to' do
  it 'loads_basic_csv_file' do 
    data = SmarterCSV.process("#{fixture_path}/basic.csv")
    data.size.should == 4
    data.each do |h|
      h.size.should <= 6
    end
  end

end
