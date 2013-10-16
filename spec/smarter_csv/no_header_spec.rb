require 'spec_helper'

fixture_path = 'spec/fixtures'

describe 'be_able_to' do
  it 'loads_csv_file_without_header' do 
    options = {:headers_in_file => false, :user_provided_headers => [:a,:b,:c,:d,:e,:f]}
    data = SmarterCSV.process("#{fixture_path}/no_header.csv", options)
    data.size.should == 5
    # all the keys should be symbols
    data.each{|item| item.keys.each{|x| x.class.should be == Symbol}}

    data.each do |item| 
      item.keys.each do |key|
        [:a,:b,:c,:d,:e,:f].should include( key )
      end
    end

    data.each do |h|
      h.size.should <= 6
    end
  end

end
