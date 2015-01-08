require 'spec_helper'

fixture_path = 'spec/fixtures'

describe 'be_able_to' do
  it 'loads_file_with_uneven_quoted_fields' do
    options = {}
    expect{SmarterCSV.process("#{fixture_path}/uneven_quoted.csv", options)}.to raise_error(SmarterCSV::InvalidCSVContent)
  end
end
