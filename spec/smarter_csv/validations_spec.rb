# frozen_string_literal: true

require 'spec_helper'

fixture_path = 'spec/fixtures'

describe 'validations' do
  let(:options) { {} }

  it 'loads basic csv file without issues' do
    data = SmarterCSV.process("#{fixture_path}/basic.csv", options)
    expect(data.size).to eq 5
  end

  [:row_sep, :col_sep, :quote_char].each do |opt|
    [nil, '', :symbol, 1].each do |val|
      context "with #{opt} set to #{val}" do
        let(:option) { opt }
        let(:value) { val }
        let(:options) { { option => value } }

        it "raises an exception if #{opt} is #{val}" do
          expect { SmarterCSV.process("#{fixture_path}/basic.csv", options) }.to raise_exception(SmarterCSV::ValidationError)
        end
      end
    end
  end
end
