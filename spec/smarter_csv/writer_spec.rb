# frozen_string_literal: true

# rubocop:disable Style/WordArray
RSpec.describe SmarterCSV::Writer do
  subject(:create_csv_file) do
    writer = SmarterCSV::Writer.new(file_path, options)
    data_batches.each { |batch| writer << batch }
    writer.finalize
  end
  let(:file_path) { '/tmp/test_output.csv' }
  let(:row_sep) { $/ } # system's row separator

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
      ],
      {name: 'Alex', country: 'USA'}
    ]
  end

  context 'simplest case: one hash given' do
    let(:options) { {} }
    let(:data) do
      { name: 'John', age: 30, city: 'New York' }
    end

    it 'writes the given headers and data correctly' do
      writer = SmarterCSV::Writer.new(file_path, options)
      writer << data
      writer.finalize
      output = File.read(file_path)

      expect(output).to include("name,age,city#{row_sep}")
      expect(output).to include("John,30,New York#{row_sep}")
    end
  end

  context 'case: array of hashes given' do
    let(:options) { {} }
    let(:data) do
      { name: 'John', age: 30, city: 'New York' }
    end

    it 'writes the given headers and data correctly' do
      writer = SmarterCSV::Writer.new(file_path, options)
      writer << data_batches[0]
      writer << data_batches[1]
      writer.finalize
      output = File.read(file_path)

      expect(output).to include("name,age,city,country,state#{row_sep}")
      expect(output).to include("John,30,New York#{row_sep}")
      expect(output).to include("Jane,25,,USA#{row_sep}")
      expect(output).to include("Mike,35,Chicago,,IL#{row_sep}")
    end
  end

  context "when deeply nested data" do
    let(:options) { {} }
    let(:data_batches) do
      [[[
        [
          { name: 'John', age: 30, city: 'New York' },
          [{ name: 'Jane', age: 25, country: 'USA' }, nil],
          []
        ],
        [
          { name: 'Mike', age: 35, city: 'Chicago', state: 'IL' }
        ]
      ]],
       {name: 'Alex', country: 'USA'}]
    end

    it 'writes the given headers and data correctly' do
      create_csv_file
      output = File.read(file_path)

      expect(output).to include("name,age,city,country,state#{row_sep}")
      expect(output).to include("John,30,New York#{row_sep}")
      expect(output).to include("Jane,25,,USA#{row_sep}")
      expect(output).to include("Mike,35,Chicago,,IL#{row_sep}")
      expect(output).to include("Alex,,,USA,#{row_sep}")
    end

    it 'works with the convenience module method' do
      SmarterCSV.generate(file_path, options) do |csv|
        data_batches.each do |data|
          csv << data
        end
      end

      output = File.read(file_path)
      expect(output).to include("name,age,city,country,state#{row_sep}")
      expect(output).to include("John,30,New York#{row_sep}")
      expect(output).to include("Jane,25,,USA#{row_sep}")
      expect(output).to include("Mike,35,Chicago,,IL#{row_sep}")
      expect(output).to include("Alex,,,USA,#{row_sep}")
    end

    context "when headers are given explicitly" do
      let(:options) { {headers: [:country, :name]} }

      it 'writes the given headers and data correctly' do
        create_csv_file

        output = File.read(file_path)

        expect(output).to include("country,name#{row_sep}")
        expect(output).to include(",John#{row_sep}")
        expect(output).to include("USA,Jane#{row_sep}")
        expect(output).to include(",Mike#{row_sep}")
        expect(output).to include("USA,Alex#{row_sep}")
      end
    end

    context "when map_headers is given explicitly" do
      let(:options) { {map_headers: {name: "Person", country: "Country"}} }

      it 'writes the given headers and data correctly' do
        create_csv_file

        output = File.read(file_path)

        expect(output).to include("Person,Country#{row_sep}")
        expect(output).to include("John,#{row_sep}")
        expect(output).to include("Jane,USA#{row_sep}")
        expect(output).to include("Mike,#{row_sep}")
        expect(output).to include("Alex,USA#{row_sep}")
      end
    end
  end

  context 'when headers are given explicitly' do
    let(:options) { { headers: %i[name age city] } }

    it 'writes the given headers and data correctly' do
      create_csv_file
      output = File.read(file_path)

      expect(output).to include("name,age,city#{row_sep}")
      expect(output).to include("John,30,New York#{row_sep}")
      expect(output).to include("Jane,25,#{row_sep}")
      expect(output).to include("Mike,35,Chicago#{row_sep}")
      expect(output).to include("Alex,,#{row_sep}")
    end
  end

  context 'when headers are automatically discovered' do
    let(:options) { {} }

    it 'writes the discovered headers and data correctly' do
      create_csv_file
      output = File.read(file_path)

      expect(output).to include("name,age,city,country,state#{row_sep}")
      expect(output).to include("John,30,New York#{row_sep}")
      expect(output).to include("Jane,25,,USA#{row_sep}")
      expect(output).to include("Mike,35,Chicago,,IL#{row_sep}")
    end
  end

  context 'when headers are mapped' do
    let(:options) do
      {
        map_headers: {
          name: 'Full Name',
          age: 'Age',
          city: 'City',
          state: 'State',
          country: 'Country',
        }
      }
    end

    it 'writes the mapped headers and data in the correct order' do
      create_csv_file

      output = File.read(file_path)

      expect(output).to include("Full Name,Age,City,State,Country#{row_sep}")
      expect(output).to include("John,30,New York,,#{row_sep}")
      expect(output).to include("Jane,25,,,USA#{row_sep}")
      expect(output).to include("Mike,35,Chicago,IL,#{row_sep}")
      expect(output).to include("Alex,,,,USA#{row_sep}")
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
      writer << [{ a: 1, b: 2 }, {c: 3}]
      writer << [{ d: 4, a: 5 }]
      writer.finalize
      output = File.read(file_path)

      expect(output).to include("a,b,c,d#{row_sep}")
      expect(output).to include("1,2#{row_sep}")
      expect(output).to include(",,3#{row_sep}")
      expect(output).to include("5,,,4#{row_sep}")
    end

    it 'appends with missing fields' do
      writer = SmarterCSV::Writer.new(file_path)
      writer << [{ a: 1, b: 2 }, { a: 3 }]
      writer.finalize

      expect(File.read(file_path)).to eq("a,b#{row_sep}1,2#{row_sep}3,#{row_sep}")
    end
  end

  context 'Finalizing the Output File' do
    it 'maps headers' do
      options = { map_headers: { a: 'A', b: 'B' } }
      writer = SmarterCSV::Writer.new(file_path, options)
      writer << [{ a: 1, b: 2 }]
      writer.finalize

      expect(File.read(file_path)).to eq("A,B#{row_sep}1,2#{row_sep}")
    end

    it 'writes header and appends content to output file' do
      writer = SmarterCSV::Writer.new(file_path)
      writer << [{ a: 1, b: 2 }]
      writer.finalize

      expect(File.read(file_path)).to eq("a,b#{row_sep}1,2#{row_sep}")
    end

    it 'properly closes the output file' do
      writer = SmarterCSV::Writer.new(file_path)
      writer << [{ a: 1, b: 2 }]
      writer.finalize

      expect(File).to be_exist(file_path)
    end
  end

  context 'CSV Field Escaping' do
    it 'does not quote fields without commas unless force_quotes is enabled' do
      writer = SmarterCSV::Writer.new(file_path)
      writer << [{ a: 'hello', b: 'world' }]
      writer.finalize

      expect(File.read(file_path)).to eq("a,b#{row_sep}hello,world#{row_sep}")
    end

    it 'quotes fields with column separator' do
      writer = SmarterCSV::Writer.new(file_path)
      writer << [{ a: 'hello, world', b: 'test' }]
      writer.finalize

      expect(File.read(file_path)).to eq("a,b#{row_sep}\"hello, world\",test#{row_sep}")
    end

    it 'quotes all fields when force_quotes is enabled' do
      options = { force_quotes: true }
      writer = SmarterCSV::Writer.new(file_path, options)
      writer << [{ a: 'hello', b: 'world' }]
      writer.finalize

      expect(File.read(file_path)).to eq("\"a\",\"b\"#{row_sep}\"hello\",\"world\"#{row_sep}")
    end

    context 'force_quotes also applies to headers' do
      let(:options) { {force_quotes: true} }
      let(:data) do
        { name: 'John', age: 30, city: 'New York' }
      end

      it 'writes the given headers and data correctly' do
        writer = SmarterCSV::Writer.new(file_path, options)
        writer << data
        writer.finalize
        output = File.read(file_path)

        expect(output).to include("\"name\",\"age\",\"city\"#{row_sep}")
        expect(output).to include("\"John\",\"30\",\"New York\"#{row_sep}")
      end
    end
  end

  context 'Edge Cases' do
    it 'handles empty hash' do
      writer = SmarterCSV::Writer.new(file_path)
      writer << [{}]
      writer.finalize

      expect(File.read(file_path)).to eq("#{row_sep}#{row_sep}")
    end

    it 'handles empty array' do
      writer = SmarterCSV::Writer.new(file_path)
      writer << []
      writer.finalize

      expect(File.read(file_path)).to eq("#{row_sep}")
    end

    it 'handles special characters in data' do
      writer = SmarterCSV::Writer.new(file_path)
      writer << [{ a: "hello#{row_sep}world", b: 'quote"test' }]
      writer.finalize

      expect(File.read(file_path)).to eq("a,b#{row_sep}\"hello#{row_sep}world\",\"quote\"test\"#{row_sep}")
    end
  end

  context 'Error Handling' do
    it 'raises an error for invalid input data' do
      expect do
        writer = SmarterCSV::Writer.new(file_path)
        writer << "this is invalid"
      end.to raise_error SmarterCSV::InvalidInputData
    end

    it 'handles file access issues' do
      allow(File).to receive(:open).and_raise(Errno::EACCES)

      expect do
        SmarterCSV::Writer.new(file_path)
      end.to raise_error(Errno::EACCES)
    end

    it 'handles tempfile issues' do
      allow(Tempfile).to receive(:new).and_raise(Errno::ENOENT)

      expect do
        SmarterCSV::Writer.new(file_path)
      end.to raise_error(Errno::ENOENT)
    end
  end
end
# rubocop:enable Style/WordArray
