# frozen_string_literal: true

require 'spec_helper'

fixture_path = 'spec/fixtures'

describe 'loading file with quoted fields' do
  let(:options) { {} }
  subject(:data) { SmarterCSV.process(file, options) }

  describe 'file quoted.csv' do
    let(:file) { "#{fixture_path}/quoted.csv" }

    it 'leaving the quotes in the data' do
      expect(data.flatten.size).to eq 4
      expect(data[1][:model]).to eq 'Venture "Extended Edition"'
      expect(data[1][:description]).to be_nil
      expect(data[2][:model]).to eq 'Venture "Extended Edition, Very Large"'
      expect(data[2][:description]).to be_nil
      expect(data[3][:description]).to eq 'MUST SELL! air, moon roof, loaded'
      data.each do |h|
        expect(h[:year].class).to eq Fixnum
        expect(h[:make]).to_not be_nil
        expect(h[:model]).to_not be_nil
        expect(h[:price].class).to eq Float
      end
    end
  end

  # quotes inside quoted fields need to be escaped by another double-quote
  describe 'file quote_char.csv' do
    let(:file) { "#{fixture_path}/quote_char.csv" }

    it 'removes quotes around quoted fields, but not inside data' do
      expect(data.length).to eq 6
      expect(data[0][:first_name]).to eq "\"John"
      expect(data[0][:last_name]).to eq "Cooke\""
      expect(data[1][:first_name]).to eq "Jam\ne\nson\""
      expect(data[2][:first_name]).to eq "\"Jean"
      expect(data[4][:first_name]).to eq "Bo\"bbie"
      expect(data[5][:first_name]).to eq 'Mica'
      expect(data[5][:last_name]).to eq 'Copeland'
    end
  end

  # NOTE: quotes inside headers need to be escaped by doubling them
  #       e.g. 'correct ""EXAMPLE""'
  #       this escaping is illegal: 'incorrect \"EXAMPLE\"' <-- this caused CSV parsing error
  #  in case of CSV parsing errirs, use :user_provided_headers, or key_mapping
  #
  describe 'file quoted2.csv' do
    let(:file) { "#{fixture_path}/quoted2.csv" }

    it 'removes quotes around headers and extra quotes inside headers' do
      expect(data.length).to eq 3
      expect(data.first.keys[2]).to eq :isbn
      expect(data.first.keys[3]).to eq :discounted_price
      expect(data[1][:author]).to eq 'Timothy "The Parser" Campbell'
    end
  end
end
