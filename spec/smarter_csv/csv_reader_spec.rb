# frozen_string_literal: true

RSpec.describe SmarterCSV::CSVReader do
  let(:fixture_path) { 'spec/fixtures/csv_reader' }
  let(:options) do
    { quote_char: '"', row_sep: "\n", col_sep: ',' }
  end

  describe '#next_char with encoding support' do
    it 'reads Shift_JIS encoded characters correctly' do
      options.merge(buffer_size: 4)
      str = "あいうえお\n".encode("Shift_JIS")
      reader = SmarterCSV::CSVReader.new(StringIO.new(str), options)

      result = +""
      while (ch = reader.next_char)
        result << ch
      end

      expect(result.encode("UTF-8")).to eq("あいうえお\n")
    end

    it 'reads ISO-8859-1 extended characters correctly' do
      options.merge(buffer_size: 2)
      str = "caf\xe9\n".dup.force_encoding("ISO-8859-1") # é in Latin-1
      reader = SmarterCSV::CSVReader.new(StringIO.new(str), options)

      result = +""
      while (ch = reader.next_char)
        result << ch
      end

      expect(result.encode("UTF-8")).to eq("café\n")
    end

    it 'returns nil or skips on malformed UTF-8 input' do
      options.merge(buffer_size: 1)
      # Invalid UTF-8: continuation byte with no leading byte
      malformed = "\xC2\xC2\xC2".b
      reader = SmarterCSV::CSVReader.new(StringIO.new(malformed), options)

      chars = []
      5.times { chars << reader.next_char }

      # Should return nil eventually without crashing
      expect(chars.compact).to all(satisfy { |c| c.valid_encoding? })
      expect(chars).to include(nil)
    end
  end

  describe '#next_char' do
    it 'reads UTF-8 characters correctly' do
      options.merge(buffer_size: 4)
      input = "abc💡🚀xyz\n"
      reader = SmarterCSV::CSVReader.new(StringIO.new(input), options)

      result = +""
      while (ch = reader.next_char)
        result << ch
      end

      expect(result).to eq(input)
    end
  end

  describe '#read_row' do
    it 'reads a single line' do
      options.merge(buffer_size: 8)
      input = "foo,bar,baz\nnext,row,here\n"
      reader = SmarterCSV::CSVReader.new(StringIO.new(input), options)

      row = reader.read_row
      expect(row).to eq("foo,bar,baz\n")

      row2 = reader.read_row
      expect(row2).to eq("next,row,here\n")
    end

    it 'returns nil at EOF' do
      options.merge(buffer_size: 4)
      reader = SmarterCSV::CSVReader.new(StringIO.new("final\n"), options)

      reader.read_row # consume line
      expect(reader.read_row).to be_nil
    end
  end

  describe '#read_rows' do
    it 'reads multiple rows' do
      options.merge(buffer_size: 6)
      input = "a,b,c\n1,2,3\nx,y,z\n"
      reader = SmarterCSV::CSVReader.new(StringIO.new(input), options)

      rows = reader.read_rows(3)
      expect(rows).to eq(["a,b,c\n", "1,2,3\n", "x,y,z\n"])
    end
  end
end
