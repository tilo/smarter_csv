# frozen_string_literal: true

require 'spec_helper'

fixture_path = 'spec/fixtures'

describe 'no header in file' do
  let(:headers) { %i[a b c d e f] }
  let(:options) { {headers_in_file: false, user_provided_headers: headers} }
  subject(:data) { SmarterCSV.process("#{fixture_path}/no_header.csv", options) }

  it 'load the correct number of records' do
    expect(data.size).to eq 5
  end

  it 'uses given symbols for all records' do
    data.each do |item|
      item.each_key do |key|
        expect(%i[a b c d e f]).to include(key)
      end
    end
  end

  it 'loads the correct data' do
    expect(data[0]).to eq({a: "Dan", b: "McAllister", c: 2, d: 0})
    expect(data[1]).to eq({a: "Lucy", b: "Laweless", d: 5, e: 0})
    expect(data[2]).to eq({a: "Miles", b: "O'Brian", c: 0, d: 0, e: 0, f: 21})
    expect(data[3]).to eq({a: "Nancy", b: "Homes", c: 2, d: 0, e: 1})
    expect(data[4]).to eq({a: "Hernán", b: "Curaçon", c: 3, d: 0, e: 0})
  end
end
