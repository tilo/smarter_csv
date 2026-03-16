# frozen_string_literal: true

fixture_path = 'spec/fixtures'

describe 'header transformations option' do
  let(:reader) { SmarterCSV::Reader.new(filename, options) }
  let(:filename) { "#{fixture_path}/with_dashes.csv" }

  [true, false].each do |acceleration|
    context "with strings as keys" do
      let(:options) { {strings_as_keys: true, acceleration: acceleration} }

      it 'loads_file_with_dashes_in_header_fields as strings' do
        data = reader.process
        expect(data.flatten.size).to eq 5
        expect(data[0]['first_name']).to eq 'Dan'
        expect(data[0]['last_name']).to eq 'McAllister'

        expect(reader.raw_header).to eq "First-Name,Last-Name,Dogs,Cats,Birds,Fish\n"
        expect(reader.headers).to eq %w[first_name last_name dogs cats birds fish]
      end
    end

    context "with symbols as keys" do
      let(:options) { {strings_as_keys: false, acceleration: acceleration} }

      it 'loads_file_with_dashes_in_header_fields as symbols' do
        data = reader.process
        expect(data.flatten.size).to eq 5
        expect(data[0][:first_name]).to eq 'Dan'
        expect(data[0][:last_name]).to eq 'McAllister'

        expect(reader.raw_header).to eq "First-Name,Last-Name,Dogs,Cats,Birds,Fish\n"
        expect(reader.headers).to eq %i[first_name last_name dogs cats birds fish]
      end
    end
  end

  # Regression test for issue #325:
  # Headers containing a quoted field with a comma (e.g. "Last, First") were
  # incorrectly split into two separate headers in v1.16.0.
  #
  # Root cause: parse_with_auto_fallback passed has_quotes: false to parse_csv_line_c
  # when the line contained no backslash, causing the C fast-path to split on every
  # comma regardless of quoting.
  #
  # NOTE: today we produce :"last,_first" - In the future we may want :"last_first" - e.g. filter out the col_sep

  describe 'quoted headers and values containing the column separator (issue #325)' do
    let(:fixture) { "#{fixture_path}/quoted_header_with_comma.csv" }

    [true, false].each do |acceleration|
      context "with acceleration: #{acceleration}" do
        it 'parses the correct number of headers' do
          data = SmarterCSV.process(fixture, acceleration: acceleration, keep_original_headers: true, strings_as_keys: true)
          expect(data.size).to eq 2
          expect(data.first.keys).to eq ['Foo', 'Last, First', 'Bar']
        end

        it 'preserves the quoted header value containing a comma' do
          data = SmarterCSV.process(fixture, acceleration: acceleration, keep_original_headers: true, strings_as_keys: true)
          expect(data.first['Last, First']).to eq 'Goodall, Jane'
          expect(data.last['Last, First']).to eq 'Smith, John'
        end

        it 'also works with default header transformations (symbol keys)' do
          data = SmarterCSV.process(fixture, acceleration: acceleration)
          # "Last, First" → downcase + spaces→underscores → :"last,_first"
          expect(data.first.keys).to include(:"last,_first")
          expect(data.first[:"last,_first"]).to eq 'Goodall, Jane'
        end
      end
    end
  end
end
