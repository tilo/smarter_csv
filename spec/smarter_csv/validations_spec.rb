# frozen_string_literal: true

require 'spec_helper'

fixture_path = 'spec/fixtures'

describe 'validations' do
  it 'loads basic csv file without issues' do
    data = SmarterCSV.process("#{fixture_path}/basic.csv", options)
    expect(data.size).to eq 5
  end

  [:row_sep, :col_sep, :quote_char].each do |option|
    [nil, :symbol, 1].each do |value|
    context "with #{option} set to #{value}" do
      let(:options) { option => value}

      it "raises an exception if #{option} is #{value}" do
        expect { SmarterCSV.process("#{fixture_path}/basic.csv", options) }.to raise_exception(SmarterCSV::ValidationError)
      end
    end
  end

  context "does not raise an exception if #{option} is a string" do
    let(:options) { option => 'a'}
    it 'loads basic csv file without issues' do
      data = SmarterCSV.process("#{fixture_path}/basic.csv", options)
      expect(data.size).to be >= 1
    end
  end
end
