require 'spec_helper'

fixture_path = 'spec/fixtures'

describe 'be_able_to' do
  it 'loads_file_with_unclosed_quoted_fields' do
    options = {}
    expect{SmarterCSV.process("#{fixture_path}/unclosed_quoted.csv", options)}.to raise_error(CSV::MalformedCSVError)
  end
end