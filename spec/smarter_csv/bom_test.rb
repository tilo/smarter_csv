# frozen_string_literal: true

require 'spec_helper'

fixture_path = 'spec/fixtures'

describe 'be_able_to' do
  it 'loads CSV file with BOM character' do
    options = {col_sep: "\cA", row_sep: "\cB", comment_regexp: /^#/}
    data = SmarterCSV.process("#{fixture_path}/bom_test.csv", options)
    expect(data.flatten.size).to eq 9

    data.each do |item|
      expect(item.keys).to eq [:user_id]
    end
    expect(data.first[:user_id]).to eq 34_194_955
    expect(data.last[:user_id]).to eq 3_019_053
  end
end
