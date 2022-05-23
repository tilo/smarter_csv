require 'spec_helper'

fixture_path = 'spec/fixtures'

describe 'be_able_to' do
  it 'loads CSV file with BOM character' do
    options = {:col_sep => "\cA", :row_sep => "\cB", :comment_regexp => /^#/}
    data = SmarterCSV.process("#{fixture_path}/bom_test.csv", options)
    data.flatten.size.should == 9
    data.each do |item|
      item.keys.should eq [:user_id]
    end
    data.first[:user_id].should eq 34194955
    data.last[:user_id].should eq 3019053
  end
end
