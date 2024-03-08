# frozen_string_literal: true

fixture_path = 'spec/fixtures'

describe 'handling of additional trailing column separators' do
  let(:file) { "#{fixture_path}/additional_separator.csv" }

  describe '' do
    let(:data) { SmarterCSV.process(file) }

    it 'reads all lines' do
      expect(data.size).to eq 5
    end

    it 'reads regular lines' do
      item = data[0]
      expect(item[:col1]).to eq 'eins'
      expect(item[:col2]).to eq 'zwei'
    end

    it 'strips single trailing col_sep character' do
      item = data[1]
      expect(item[:col1]).to eq 'uno'
      expect(item[:col2]).to eq 'dos'
    end

    it 'strips multiple trailing col_sep characters' do
      item = data[2]
      expect(item[:col1]).to eq 'one'
      expect(item[:col2]).to eq 'two'
    end

    it 'strips multiple trailing col_sep chars' do
      item = data[3]
      expect(item[:col1]).to eq 'ichi'
      expect(item[:col2]).to eq nil
    end

    it 'strips multiple trailing col_sep chars' do
      item = data[4]
      expect(item[:col1]).to eq 'un'
      expect(item[:col2]).to eq nil
    end
  end
end
