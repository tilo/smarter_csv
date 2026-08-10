# frozen_string_literal: true

fixture_path = 'spec/fixtures'

describe 'no header in file' do
  subject(:data) { SmarterCSV.process("#{fixture_path}/no_header.csv", options) }

  [true, false].each do |acceleration|
    context "with#{acceleration ? '' : 'out'} acceleration" do
      context 'without special options' do
        let(:options) { {acceleration: acceleration} }

        it 'does not raise an exception (first data row is treated as headers)' do
          # There is no good way to detect a file has no header line.
          # Previously, this accidentally raised DuplicateHeaders because empty headers
          # with duplicate_header_suffix: '' (default) produced a name that collided with a
          # data field ("" + "" + 2 = "2", which was also a header).
          # Now that empty headers get auto-named via missing_header_prefix (e.g. column_1,
          # column_2), there is no collision and no exception is raised.
          expect{ data }.not_to raise_exception
        end
      end

      context 'with setting headers_in_file to false' do
        let(:options) { {headers_in_file: false, acceleration: acceleration} }

        it 'raises an exception' do
          expect{ data }.to raise_exception(
            SmarterCSV::IncorrectOption,
            /If :headers_in_file is set to false, you have to provide :user_provided_headers/
          )
        end
      end

      context 'when user_provided_headers given' do
        let(:headers) { %i[a b c d e f] }
        let(:options) { {headers_in_file: false, user_provided_headers: headers, acceleration: acceleration} }

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
  end

  # The user_provided_headers array belongs to the caller. When rows contain more columns
  # than headers, the reader extends its internal header list with column_N entries — it
  # must not append them into the caller's array (or into options[:user_provided_headers],
  # where a reused options hash would silently change behavior on the next file).
  context 'when rows have more columns than user_provided_headers' do
    it 'does not mutate the array passed in by the caller' do
      my_headers = [:a, :b]
      result = SmarterCSV.process(StringIO.new("1,2,3,4\n"), user_provided_headers: my_headers, headers_in_file: false)
      expect(result).to eq [{ a: 1, b: 2, column_3: 3, column_4: 4 }]
      expect(my_headers).to eq [:a, :b]
    end
  end

  # A nil entry in user_provided_headers means "drop this column" — the nil key must not
  # appear in the row hashes, on either path.
  context 'when user_provided_headers contains nil (both paths)' do
    [true, false].each do |acceleration|
      it "drops the nil-keyed column (acceleration: #{acceleration})" do
        result = SmarterCSV.process(StringIO.new("1,2\n3,4\n"), user_provided_headers: [nil, :b], headers_in_file: false, remove_empty_values: false, acceleration: acceleration)
        expect(result).to eq [{ b: 2 }, { b: 4 }]
      end
    end
  end
end
