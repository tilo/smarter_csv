# frozen_string_literal: true

require 'spec_helper'

fixture_path = 'spec/fixtures'

describe 'be_able_to' do
  it 'loads_file_with_different_column_separator' do
    options = {col_sep: ';'}
    data = SmarterCSV.process("#{fixture_path}/separator.csv", options)
    data.flatten.size.should eq 3
  end

  it 'loads_file_with_different_column_separator and v1 defaults' do
    options = {col_sep: ';', defaults: 'v1' }
    data = SmarterCSV.process("#{fixture_path}/separator.csv", options)
    data.flatten.size.should eq 3
  end

  it 'loads_file_with_different_column_separator and safe defaults' do
    options = {col_sep: ';', defaults: 'safe' }
    data = SmarterCSV.process("#{fixture_path}/separator.csv", options)
    data.flatten.size.should eq 3
  end
end
