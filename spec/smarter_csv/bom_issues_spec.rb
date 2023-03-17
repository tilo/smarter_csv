# frozen_string_literal: true

require 'spec_helper'

fixture_path = 'spec/fixtures'

describe 'BOM Tests' do
  context 'when given CSV file with BOM issue' do
    let(:file) { "#{fixture_path}/bom_issue.csv" }

    it 'loads the file with the correct headers' do
      data = SmarterCSV.process(file)
      expect(data.size).to eq 2
      expect(data[0][:some_id]).to eq true # untreated BOM issue would taint first column's symbol with the BOM
      expect(data[0].keys.sort).to eq [:fuzzboxes, :type, :some_id]
      expect[data[0][:some_id]].to eq 42766805
      expect[data[1][:some_id]].to eq 38759150
    end
  end

  # this was the old test
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
