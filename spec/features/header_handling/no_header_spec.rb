# frozen_string_literal: true

fixture_path = 'spec/fixtures'

describe 'no header in file' do
  subject(:data) { SmarterCSV.process("#{fixture_path}/no_header.csv", options) }

  context 'without special options' do
    let(:options) { {} }

    it 'raises an exception' do
      # there is no good way to detect a file has no header line,
      # but there is a chance that some fields are empty, which causes a uplicateHeaders exception
      #
      expect{ data }.to raise_exception(SmarterCSV::DuplicateHeaders)
    end
  end

  context 'with setting headers_in_file to false' do
    let(:options) { {headers_in_file: false} }

    it 'raises an exception' do
      expect{ data }.to raise_exception(
        SmarterCSV::IncorrectOption,
        /If :headers_in_file is set to false, you have to provide :user_provided_headers/
      )
    end
  end

  context 'when user_provided_headers given' do
    let(:headers) { %i[a b c d e f] }
    let(:options) { {headers_in_file: false, user_provided_headers: headers} }

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
end
