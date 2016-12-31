require 'spec_helper'

fixture_path = 'spec/fixtures'

describe 'be_able_to' do
  it 'loads_file_with_dashes_in_header_fields as strings' do
    options = {:strings_as_keys => true}
    data = SmarterCSV.process("#{fixture_path}/with_dashes.csv", options)
    expect(data.flatten.size).to eq(5)
    expect(data[0]['first_name']).to eq 'Dan'
    expect(data[0]['last_name']).to eq 'McAllister'
  end

  it 'loads_file_with_dashes_in_header_fields as symbols' do
    options = {:strings_as_keys => false}
    data = SmarterCSV.process("#{fixture_path}/with_dashes.csv", options)
    expect(data.flatten.size).to eq(5)
    expect(data[0][:first_name]).to eq 'Dan'
    expect(data[0][:last_name]).to eq 'McAllister'
  end
end
