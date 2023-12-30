# frozen_string_literal: true

require 'spec_helper'

fixture_path = 'spec/fixtures'

describe 'can handle the difficult CSV file' do
  it 'loads the data with default values' do
    data = SmarterCSV.process("#{fixture_path}/hard_sample.csv")
    expect(data.size).to eq 1
    item = data.first
    expect(item.keys.count).to eq 48
    expect(item[:name]).to eq '#MR1220817'
    expect(item[:shipping_method]).to eq 'Livraison Standard GRATUITE, 2-5 jours avec suivi'
    expect(item[:lineitem_name]).to eq 'Cire Épilation Nacrée'
    expect(item[:phone]).to eq 3_366_012_111_111
  end

  # the main problem is the data line starting with a # character, but not being a comment
  it 'fails to load the CSV file with incorrectly set comment_regexp' do
    options = {comment_regexp: /\A#/ }
    data = SmarterCSV.process("#{fixture_path}/hard_sample.csv", options)
    expect(data.size).to eq 0
  end
end
