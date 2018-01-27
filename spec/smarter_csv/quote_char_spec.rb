
require 'spec_helper'

fixture_path = 'spec/fixtures'

describe 'be able to' do
  it 'remove quotes from quoted fields' do
    options = {}
    data = SmarterCSV.process("#{fixture_path}/quote_char.csv", options)

    expect(data.length).to eql(6)
    expect(data[1][:first_name]).to eql("Jam\ne\nson")
    expect(data[2][:first_name]).to eql("Jean")
  end
end
