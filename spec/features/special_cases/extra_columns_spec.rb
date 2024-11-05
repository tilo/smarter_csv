# frozen_string_literal: true

fixture_path = 'spec/fixtures'

# when rows with extra columns are present, we want to be robust against this error, and we auto-generate headers
#
describe 'CSV file with more columns that shown in header' do
  let(:csv_path) { "#{fixture_path}/extra_columns.csv" }

  [true, false].each do |bool|
    context "with#{bool ? ' C-' : 'out '}acceleration" do
      let(:options) { { acceleration: bool } }
      let(:reader) { SmarterCSV::Reader.new(csv_path, options) }

      context "when strict mode" do
        before do
          options.merge!(strict: true)
        end

        it "raises an exception" do
          expect{reader.process}.to raise_exception SmarterCSV::HeaderSizeMismatch, "extra columns detected on line 2"
        end
      end

      it "reads all lines of the file" do
        data = reader.process
        expect(data.size).to eq 5
      end

      context "when default behavior" do
        # default behavior is to remove empty values
        # it finds column_11, but it is empty, and will not show up as a hash
        it "generates all extra columns" do
          reader.process
          expect(reader.headers).to eq %i[one two three four five six column_7 column_8 column_9 column_10 column_11]
        end

        it "parses all rows correctly" do
          data = reader.process
          expect(data[0]).to eq({one: 1, two: 2, five: 5, column_8: 8, column_9: 9})
          expect(data[1]).to eq({one: 1, two: 2, three: 3, four: 4, five: 5, six: 6})
          expect(data[2]).to eq({one: 1, two: 2, three: 3, four: 4, five: 5, six: 6})
          expect(data[3]).to eq({one: 1, column_10: 10})
          expect(data[4]).to eq({one: 1, column_10: 10})
        end
      end

      context "when keeping empty values" do
        before do
          options.merge!(remove_empty_values: false)
        end

        it "generates all extra columns" do
          reader.process
          expect(reader.headers).to eq %i[one two three four five six column_7 column_8 column_9 column_10 column_11]
        end

        it "parses all rows correctly" do
          data = reader.process
          expect(data[0]).to eq({one: 1, two: 2, three: '', four: '', five: 5, six: '', column_7: '', column_8: 8, column_9: 9})
          expect(data[1]).to eq({one: 1, two: 2, three: 3, four: 4, five: 5, six: 6, column_7: nil, column_8: nil, column_9: nil})
          expect(data[2]).to eq({one: 1, two: 2, three: 3, four: 4, five: 5, six: 6, column_7: '', column_8: nil, column_9: nil})
          expect(data[3]).to eq({one: 1, two: '', three: '', four: '', five: '', six: '', column_7: '', column_8: '', column_9: '', column_10: 10})
          expect(data[4]).to eq({one: 1, two: '', three: '', four: '', five: '', six: '', column_7: '', column_8: '', column_9: '', column_10: 10, column_11: ''})
        end
      end

      context "when missing_header_prefix is changed" do
        before do
          options.merge!(missing_header_prefix: 'col_')
        end

        it "generates all extra columns" do
          reader.process
          expect(reader.headers).to eq %i[one two three four five six col_7 col_8 col_9 col_10 col_11]
        end

        it "parses all rows correctly" do
          data = reader.process
          expect(data[0]).to eq({one: 1, two: 2, five: 5, col_8: 8, col_9: 9})
          expect(data[1]).to eq({one: 1, two: 2, three: 3, four: 4, five: 5, six: 6})
          expect(data[2]).to eq({one: 1, two: 2, three: 3, four: 4, five: 5, six: 6})
          expect(data[3]).to eq({one: 1, col_10: 10})
          expect(data[4]).to eq({one: 1, col_10: 10})
        end
      end

      context "when user did not provide enough headers manually" do
        before do
          options.merge!(headers_in_file: true, user_provided_headers: %i[a b c d e f])
        end

        it "generates all extra columns" do
          reader.process
          expect(reader.headers).to eq %i[a b c d e f column_7 column_8 column_9 column_10 column_11]
        end

        it "parses all rows correctly" do
          data = reader.process
          expect(data[0]).to eq({a: 1, b: 2, e: 5, column_8: 8, column_9: 9})
          expect(data[1]).to eq({a: 1, b: 2, c: 3, d: 4, e: 5, f: 6})
          expect(data[2]).to eq({a: 1, b: 2, c: 3, d: 4, e: 5, f: 6})
          expect(data[3]).to eq({a: 1, column_10: 10})
          expect(data[4]).to eq({a: 1, column_10: 10})
        end
      end
    end
  end
end
