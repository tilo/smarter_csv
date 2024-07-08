# frozen_string_literal: true

fixture_path = 'spec/fixtures'

describe 'header transformations option' do
  let(:reader) { SmarterCSV::Reader.new(filename, options) }
  let(:filename) { "#{fixture_path}/with_dashes.csv" }

  context "with strings as keys" do
    let(:options) { {strings_as_keys: true} }

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
    let(:options) { {strings_as_keys: false} }

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
