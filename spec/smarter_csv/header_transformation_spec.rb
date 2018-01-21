require 'spec_helper'

fixture_path = 'spec/fixtures'

describe 'processes files' do

  it 'with dashes in header fields as strings' do
    options = {
      :header_transformations => [ :keys_as_strings ],
    }
    data = SmarterCSV.process("#{fixture_path}/with_dashes.csv", options)

    data.flatten.size.should == 5
    data[0]['first_name'].should eq 'Dan'
    data[0]['last_name'].should eq 'McAllister'
  end

  it 'with dashes in header fields as symbols' do
    options = {
      :header_transformations => [ :keys_as_symbols ],
    }
    data = SmarterCSV.process("#{fixture_path}/with_dashes.csv", options)

    data.flatten.size.should == 5
    data[0][:first_name].should eq 'Dan'
    data[0][:last_name].should eq 'McAllister'
  end
end
