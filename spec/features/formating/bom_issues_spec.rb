# frozen_string_literal: true

fixture_path = 'spec/fixtures'

describe 'BOM Tests' do
  let(:options) { {} }
  subject(:data) { SmarterCSV.process(file, options) }

  %w[fffe feff efbbbf fffe0000 0000feff].each do |bom|
    context "when given CSV file with UTF-8 BOM #{bom}" do
      let(:file) { "#{fixture_path}/bom_test_#{bom}.csv" }

      it 'loads all lines in the file' do
        expect(data.size).to eq 2
      end

      it 'loads the file with the correct headers' do
        expect(data[0].keys).to eq [:some_id, :type, :fuzzboxes]
      end

      it 'strips the BOM' do
        expect(data[0][:some_id]).not_to be_nil # untreated BOM issue would taint first column's symbol with the BOM
      end

      it 'can access the first column values' do
        expect(data[0][:some_id]).to eq 42_766_805
        expect(data[1][:some_id]).to eq 38_759_150
      end

      # we fake that there is no header in the file
      context 'when no header in file' do
        let(:options) { {headers_in_file: false, user_provided_headers: %i[one two three]} }

        it 'loads all lines in the file' do
          expect(data.size).to eq 3 # it interprets the first line as data
        end

        it 'loads the file with the correct headers' do
          expect(data[0].keys).to eq [:one, :two, :three]
        end

        it 'strips the BOM' do
          expect(data[0][:one]).not_to be_nil # untreated BOM issue would taint first column's symbol with the BOM
        end

        it 'can access the first column values' do
          expect(data[0][:one]).to eq 'some_id'
          expect(data[1][:one]).to eq 42_766_805
          expect(data[2][:one]).to eq 38_759_150
        end
      end
    end
  end
end
