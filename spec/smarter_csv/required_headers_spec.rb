# frozen_string_literal: true

require 'spec_helper'

fixture_path = 'spec/fixtures'

describe 'required_headers' do
  let(:options) { {} }
  subject(:data) { SmarterCSV.process("#{fixture_path}/required_headers.csv", options) }

  it 'loads the csv file without issues' do
    expect(data.size).to eq 3
    expect(data[0][:name]).to eq 'Bill'
  end

  it 'uses the attribute name after header transformation' do
    options[:key_mapping] = {name: :first_name}
    options[:required_headers] = [:first_name]
    expect(data.size).to eq 3
    expect(data[0][:first_name]).to eq 'Bill'
  end

  it 'raises an exception if the raw header name is used' do
    options[:key_mapping] = {name: :first_name}
    options[:required_headers] = [:name]
    expect{ data }.to raise_error(SmarterCSV::MissingHeaders)
  end
end
