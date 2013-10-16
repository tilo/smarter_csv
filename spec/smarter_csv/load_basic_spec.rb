require 'spec_helper'

fixture_path = 'spec/fixtures'

describe 'be_able_to' do
  it 'loads_basic_csv_file' do 
    data = SmarterCSV.process("#{fixture_path}/basic.csv")
    data.size.should == 5

    # all the keys should be symbols
    data.each{|item| item.keys.each{|x| x.class.should be == Symbol}}
    data.each do |h|
      h.keys.each do |key|
        [:first_name, :last_name, :dogs, :cats, :birds, :fish].should include( key )
      end
      h.size.should <= 6
    end
  end

end
