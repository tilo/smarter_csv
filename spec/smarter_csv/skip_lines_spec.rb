require 'spec_helper'

fixture_path = 'spec/fixtures'

describe 'be_able_to' do
  it 'loads_csv_file_skipping_lines' do
    options = {skip_lines: 3}
    data = SmarterCSV.process("#{fixture_path}/skip_lines.csv", options)
    data.size.should == 4

    data.each do |item|
      item.keys.each do |key|
        [:first_name,:last_name,:dogs,:cats,:birds,:fish].should include(key)
      end
    end
  end

  it 'loads_csv_with_user_defined_headers' do
    options = {:skip_lines => 3, :headers_in_file => true, :user_provided_headers => [:a,:b,:c,:d,:e,:f]}
    data = SmarterCSV.process("#{fixture_path}/skip_lines.csv", options)
    data.size.should == 4
  
    data.each do |item|
      item.keys.each do |key|
        [:a,:b,:c,:d,:e,:f].should include( key )
      end
    end
  end
end
