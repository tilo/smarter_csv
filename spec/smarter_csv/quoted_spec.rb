require 'spec_helper'

fixture_path = 'spec/fixtures'

describe 'be_able_to' do
  it 'loads_file_with_quoted_fields' do 
    options = {}
    data = SmarterCSV.process("#{fixture_path}/quoted.csv", options)
    expect(data.flatten.size).to eq 4
    expect(data[1][:description]).to be_nil
    expect(data[2][:description]).to be_nil
  end
end
