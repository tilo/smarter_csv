# frozen_string_literal: true

require 'spec_helper'

fixture_path = 'spec/fixtures'

describe 'be_able_to' do
  it 'remove_empty_values' do
    options = {row_sep: :auto, remove_empty_values: true}
    data = SmarterCSV.process("#{fixture_path}/empty.csv", options)
    expect(data.size).to eq 1

    expect(data[0].keys).to eq(%i[not_empty_1 not_empty_2 not_empty_3])
  end
end
