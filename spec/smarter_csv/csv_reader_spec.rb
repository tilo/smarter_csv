# frozen_string_literal: true

# require 'buffered_io/buffered_io'
# require 'smarter_csv/csv_reader'
# require 'stringio'

RSpec.describe SmarterCSV::CSVReader do
  let(:fixture_path) { 'spec/fixtures/csv_reader' }
  let(:options) do
    { quote_char: '"', row_sep: "\n", col_sep: ',' }
  end

  describe '#next_char' do
    it 'reads UTF-8 characters correctly' do
      input = "abc💡🚀xyz\n"
      io = SmarterCSV::BufferedIO.new(StringIO.new(input), 4)
      reader = SmarterCSV::CSVReader.new(io, options)

      result = +""
      while (ch = reader.next_char)
        result << ch
      end

      expect(result).to eq(input)
    end
  end

  describe '#read_row' do
    it 'reads a single line' do
      input = "foo,bar,baz\nnext,row,here\n"
      io = SmarterCSV::BufferedIO.new(StringIO.new(input), 8)
      reader = SmarterCSV::CSVReader.new(io, options)

      row = reader.read_row
      expect(row).to eq("foo,bar,baz\n")

      row2 = reader.read_row
      expect(row2).to eq("next,row,here\n")
    end

    it 'returns nil at EOF' do
      io = SmarterCSV::BufferedIO.new(StringIO.new("final\n"), 4)
      reader = SmarterCSV::CSVReader.new(io, options)

      reader.read_row # consume line
      expect(reader.read_row).to be_nil
    end
  end

  describe '#read_rows' do
    it 'reads multiple rows' do
      input = "a,b,c\n1,2,3\nx,y,z\n"
      io = SmarterCSV::BufferedIO.new(StringIO.new(input), 6)
      reader = SmarterCSV::CSVReader.new(io, options)

      rows = reader.read_rows(3)
      expect(rows).to eq(["a,b,c\n", "1,2,3\n", "x,y,z\n"])
    end
  end
end
