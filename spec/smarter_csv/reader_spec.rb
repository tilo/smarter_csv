# frozen_string_literal: true

RSpec.describe SmarterCSV::Reader do
  let(:fixture_path) { 'spec/fixtures' }

  describe "initialize" do
    let(:filename) { "#{fixture_path}/basic.csv" }

    it "initializes the internal state" do
      reader = SmarterCSV::Reader.new(filename)
      expect(reader.chunk_count).to eq 0
      expect(reader.csv_line_count).to eq 0
      expect(reader.file_line_count).to eq 0
      expect(reader.enforce_utf8).to eq false
      expect(reader.has_rails).to eq false
      expect(reader.input).to eq filename
      expect(reader.headers).to be_nil
      expect(reader.raw_header).to be_nil
      expect(reader.headerA).to eq []
      expect(reader.warnings).to be_empty
      expect(reader.errors).to be_empty
      expect(reader.result).to eq []
      # initializes to the default options
      expect(reader.options).to eq SmarterCSV::Options::DEFAULT_OPTIONS
    end

    it "sets options" do
      reader = SmarterCSV::Reader.new(
        filename, {
          col_sep: ";", row_sep: "\r\n", quote_char: "'",
          accelleration: false,
        }
      )
      expect(reader.options[:col_sep]).to eq ';'
      expect(reader.options[:row_sep]).to eq "\r\n"
      expect(reader.options[:quote_char]).to eq "'"
      expect(reader.options[:accelleration]).to eq false
    end
  end
end
