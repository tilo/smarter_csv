# frozen_string_literal: true

RSpec.describe SmarterCSV::CSVReader do
  let(:fixture_path) { 'spec/fixtures/csv_reader' }
  let(:options) do
    { quote_char: '"', row_sep: "\n", col_sep: ',' }
  end

  describe '#read_row_as_fields with custom separators' do
    let(:data) do
      [
        %w[a b c].join(options[:col_sep]),
        %w[x y z].join(options[:col_sep])
      ]
    end
    let(:input) do
      data.join(options[:row_sep])
    end

    ["\n", "\r", "\n\r"].each do |row_sep|
      it "parses rows with a custom row_sep #{row_sep.inspect}" do
        options = { row_sep: row_sep, col_sep: ',', quote_char: '"', buffer_size: 8 }
        data = [
          %w[a b c].join(options[:col_sep]),
          %w[x y z].join(options[:col_sep])
        ]
        input = data.join(options[:row_sep])
        reader = SmarterCSV::CSVReader.new(StringIO.new(input), options)
        expect(reader.read_row_as_fields).to eq(%w[a b c])
        expect(reader.read_row_as_fields).to eq(%w[x y z])
      end
    end

    [',', ':', "\t", '|'].each do |col_sep|
      it "parses fields with custom col_sep #{col_sep.inspect}" do
        options = { col_sep: col_sep, row_sep: "\n", quote_char: '"', buffer_size: 8 }
        data = [
          %w[a b c].join(col_sep),
          %w[x y z].join(col_sep)
        ]
        input = data.join(options[:row_sep])
        reader = SmarterCSV::CSVReader.new(StringIO.new(input), options)
        expect(reader.read_row_as_fields).to eq(%w[a b c])
        expect(reader.read_row_as_fields).to eq(%w[x y z])
      end
    end

    ['"', "'", "<>"].each do |quote_char|
      it "parses quoted fields with custom quote_char #{quote_char.inspect}" do
        options = { col_sep: ',', row_sep: "\n", quote_char: quote_char, buffer_size: 8 }
        data = [
          %w[a b c].join(options[:col_sep]),
          %w[x y z].join(options[:col_sep]),
          [
            %{5""},
            %{5'11""},
            %{"5'11"""}
          ].join(options[:col_sep])
        ]
        input = data.join(options[:row_sep])
        reader = SmarterCSV::CSVReader.new(StringIO.new(input), options)
        expect(reader.read_row_as_fields).to eq(%w[a b c])
        expect(reader.read_row_as_fields).to eq(%w[x y z])
        expect(reader.read_row_as_fields).to eq(['5"', '5\'11"', '5\'11"'])
      end
    end

    context "when quote_char inside fields" do |_variable|
      let(:data) do
        [
          [%{5""}, %{5'11""}, %q{"5'11"""}].join(options[:col_sep])
        ]
      end

      it 'parses quoted fields with quote_char "' do
        options = { col_sep: ',', row_sep: "\n", quote_char: '"', buffer_size: 8 }
        reader = SmarterCSV::CSVReader.new(StringIO.new(input), options)
        expect(reader.read_row_as_fields).to eq(['5"', '5\'11"', '5\'11"'])
      end
    end

    it 'handles quoted fields containing col_sep and row_sep' do
      input = "\"a,b\n\",\"x,y\"\n"
      options = { col_sep: ',', row_sep: "\n", quote_char: '"', buffer_size: 8 }
      reader = SmarterCSV::CSVReader.new(StringIO.new(input), options)
      expect(reader.read_row_as_fields).to eq(["a,b\n", "x,y"])
    end
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
    ["\n", "\r", "\n\r"].each do |row_sep|
      it "reads a single line with a custom row_sep #{row_sep}" do
        options.merge(buffer_size: 8)
        input = "foo,bar,baz#{row_sep}next,row,here#{row_sep}"
        reader = SmarterCSV::CSVReader.new(StringIO.new(input), options)

        row = reader.read_row
        expect(row).to eq("foo,bar,baz#{row_sep}")

        row2 = reader.read_row
        expect(row2).to eq("next,row,here#{row_sep}")
      end
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
