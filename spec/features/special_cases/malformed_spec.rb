# frozen_string_literal: true

fixture_path = 'spec/fixtures'

# according to RFC-4180 quotes inside of "words" shouldbe doubled, but our parser is robust against that.

[true, false].each do |bool|
  describe "handling files with escaped quote chars with#{bool ? ' C-' : 'out '}acceleration" do
    let(:options) { { acceleration: bool } }
    let(:reader) { SmarterCSV::Reader.new(csv_path, options) }

    describe 'malformed CSV quotes' do
      context "malformed quotes in header" do
        let(:csv_path) { "#{fixture_path}/malformed_header.csv" }
        it 'should be resilient against single quotes' do
          data = reader.process
          expect(data[0]).to eq({name: "Arnold Schwarzenegger", dobdob: "1947-07-30"})
          expect(data[1]).to eq({name: "Jeff Bridges", dobdob: "1949-12-04"})
        end
      end

      context "malformed quotes in content" do
        let(:csv_path) { "#{fixture_path}/malformed.csv" }

        it 'should be resilient against single quotes' do
          data = reader.process
          expect(data[0]).to eq({name: "Arnold Schwarzenegger", dob: "1947-07-30"})
          expect(data[1]).to eq({name: "Jeff \"the dude\" Bridges", dob: "1949-12-04"})
        end
      end

      context "malformed quotes in content" do
        let(:csv_path) { "#{fixture_path}/malformed_data_eof.csv" }

        it 'should raise MalformedCSV error' do
          expect { reader.process }.to raise_error(SmarterCSV::MalformedCSV, "Unclosed quoted field detected in multiline data")
        end
      end

      context "malformed quotes in content" do
        let(:csv_path) { "#{fixture_path}/malformed_data_gobbled.csv" }

        it 'should raise MalformedCSV error' do
          expect { reader.process }.to raise_error(SmarterCSV::MalformedCSV, /Unclosed quoted field detected/)
        end
      end
    end

  end
end
