# frozen_string_literal: true

RSpec.describe SmarterCSV::Writer do
  subject(:create_csv_file) do
    writer = SmarterCSV::Writer.new(file_path, options)
    data_batches.each { |batch| writer.append(batch) }
    writer.finalize
  end
  let(:file_path) { '/tmp/test_output.csv' }

  after(:each) do
    File.delete(file_path) if File.exist?(file_path)
  end

  let(:data_batches) do
    [
      [
        { name: 'John', age: 30, city: 'New York' },
        { name: 'Jane', age: 25, country: 'USA' }
      ],
      [
        { name: 'Mike', age: 35, city: 'Chicago', state: 'IL' }
      ]
    ]
  end

  context 'when headers are given in advance' do
    let(:options) { { headers: %i[name age city] } }

    it 'writes the given headers and data correctly' do
      create_csv_file
      output = File.read(file_path)

      expect(output).to include("name,age,city,country,state\n")
      expect(output).to include("John,30,New York\n")
      expect(output).to include("Jane,25,,USA\n")
      expect(output).to include("Mike,35,Chicago,,IL\n")
    end
  end

  context 'when headers are automatically discovered' do
    let(:options) { {} }

    it 'writes the discovered headers and data correctly' do
      create_csv_file
      output = File.read(file_path)

      expect(output).to include("name,age,city,country,state\n")
      expect(output).to include("John,30,New York\n")
      expect(output).to include("Jane,25,,USA\n")
      expect(output).to include("Mike,35,Chicago,,IL\n")
    end
  end

  context 'when headers are mapped' do
    let(:options) do
      {
        map_headers: {
          name: 'Full Name',
          age: 'Age',
          city: 'City',
          country: 'Country',
          state: 'State',
        }
      }
    end

    it 'writes the mapped headers and data correctly' do
      create_csv_file
      output = File.read(file_path)

      expect(output).to include("Full Name,Age,City,Country,State\n")
      expect(output).to include("John,30,New York\n")
      expect(output).to include("Jane,25,,USA\n")
      expect(output).to include("Mike,35,Chicago,,IL\n")
    end
  end

  context 'Initialization with Default Options' do
    it 'initializes with default options' do
      writer = SmarterCSV::Writer.new(file_path)
      expect(writer.instance_variable_get(:@discover_headers)).to be true
      expect(writer.instance_variable_get(:@headers)).to eq([])
      expect(writer.instance_variable_get(:@col_sep)).to eq(',')
    end
  end

  context 'Initialization with Custom Options' do
    it 'initializes with custom options' do
      options = { discover_headers: false, headers: ['a', 'b'], col_sep: ';', force_quotes: true, map_headers: { 'a' => 'A' } }
      writer = SmarterCSV::Writer.new(file_path, options)
      expect(writer.instance_variable_get(:@discover_headers)).to be false
      expect(writer.instance_variable_get(:@headers)).to eq(['a', 'b'])
      expect(writer.instance_variable_get(:@col_sep)).to eq(';')
      expect(writer.instance_variable_get(:@force_quotes)).to be true
      expect(writer.instance_variable_get(:@map_headers)).to eq({ 'a' => 'A' })
    end
  end

  context 'Appending Data' do
    it 'appends multiple hashes over multiple calls' do
      writer = SmarterCSV::Writer.new(file_path)
      writer.append([{ a: 1, b: 2 }, {c: 3}])
      writer.append([{ d: 4, a: 5 }])
      writer.finalize
      output = File.read(file_path)

      expect(output).to include("a,b,c,d\n")
      expect(output).to include("1,2\n")
      expect(output).to include(",,3\n")
      expect(output).to include("5,,,4\n")
    end

    it 'appends with existing headers' do
      options = { headers: [:a] }
      writer = SmarterCSV::Writer.new(file_path, options)
      writer.append([{ a: 1, b: 2 }])
      writer.finalize

      expect(File.read(file_path)).to eq("a,b\n1,2\n")
    end

    it 'appends with missing fields' do
      writer = SmarterCSV::Writer.new(file_path)
      writer.append([{ a: 1, b: 2 }, { a: 3 }])
      writer.finalize

      expect(File.read(file_path)).to eq("a,b\n1,2\n3,\n")
    end
  end

  context 'Finalizing the Output File' do
    it 'maps headers' do
      options = { map_headers: { a: 'A', b: 'B' } }
      writer = SmarterCSV::Writer.new(file_path, options)
      writer.append([{ a: 1, b: 2 }])
      writer.finalize

      expect(File.read(file_path)).to eq("A,B\n1,2\n")
    end

    it 'writes header and appends content to output file' do
      writer = SmarterCSV::Writer.new(file_path)
      writer.append([{ a: 1, b: 2 }])
      writer.finalize

      expect(File.read(file_path)).to eq("a,b\n1,2\n")
    end

    it 'properly closes the output file' do
      writer = SmarterCSV::Writer.new(file_path)
      writer.append([{ a: 1, b: 2 }])
      writer.finalize

      expect(File).to be_exist(file_path)
    end
  end

  context 'CSV Field Escaping' do
    it 'does not quote fields without commas unless force_quotes is enabled' do
      writer = SmarterCSV::Writer.new(file_path)
      writer.append([{ a: 'hello', b: 'world' }])
      writer.finalize

      expect(File.read(file_path)).to eq("a,b\nhello,world\n")
    end

    it 'quotes fields with column separator' do
      writer = SmarterCSV::Writer.new(file_path)
      writer.append([{ a: 'hello, world', b: 'test' }])
      writer.finalize

      expect(File.read(file_path)).to eq("a,b\n\"hello, world\",test\n")
    end

    it 'quotes all fields when force_quotes is enabled' do
      options = { force_quotes: true }
      writer = SmarterCSV::Writer.new(file_path, options)
      writer.append([{ a: 'hello', b: 'world' }])
      writer.finalize

      expect(File.read(file_path)).to eq("a,b\n\"hello\",\"world\"\n")
    end
  end

  context 'Edge Cases' do
    it 'handles empty hash' do
      writer = SmarterCSV::Writer.new(file_path)
      writer.append([{}])
      writer.finalize

      expect(File.read(file_path)).to eq("\n\n")
    end

    it 'handles empty array' do
      writer = SmarterCSV::Writer.new(file_path)
      writer.append([])
      writer.finalize

      expect(File.read(file_path)).to eq("\n")
    end

    it 'handles special characters in data' do
      writer = SmarterCSV::Writer.new(file_path)
      writer.append([{ a: "hello\nworld", b: 'quote"test' }])
      writer.finalize

      expect(File.read(file_path)).to eq("a,b\n\"hello\nworld\",\"quote\"test\"\n")
    end
  end

  context 'Error Handling' do
    it 'handles file access issues' do
      allow(File).to receive(:open).and_raise(Errno::EACCES)

      expect {
        SmarterCSV::Writer.new(file_path)
      }.to raise_error(Errno::EACCES)
    end

    it 'handles tempfile issues' do
      allow(Tempfile).to receive(:new).and_raise(Errno::ENOENT)

      expect {
        SmarterCSV::Writer.new(file_path)
      }.to raise_error(Errno::ENOENT)
    end
  end
end
