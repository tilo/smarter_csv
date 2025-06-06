# frozen_string_literal: true

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

  context 'when different input data' do
    context 'when empty data is handed in' do
      let(:options) { {} }

      subject(:write_csv) do
        SmarterCSV.generate(file_path, options) do |csv_writer|
          csv_writer << data
        end
      end

      context 'when nil is passed in' do
        let(:data) { nil }
        it 'does not generate output' do
          write_csv
          output = File.read(file_path)
          expect(output).to eq ''
        end
      end

      context 'when {} is passed in' do
        let(:data) { {} }
        it 'does not generate output' do
          write_csv
          output = File.read(file_path)
          expect(output).to eq ''
        end
      end

      context 'when [] is passed in' do
        let(:data) { [] }
        it 'does not generate output' do
          write_csv
          output = File.read(file_path)
          expect(output).to eq ''
        end
      end

      context 'when [{},nil] is passed in' do
        let(:data) { [{}, nil] }
        it 'does not generate output' do
          write_csv
          output = File.read(file_path)
          expect(output).to eq ''
        end
      end

      context 'when [nil, {}, [], [{},nil]] is passed in' do
        let(:data) { [nil, {}, [], [{}, nil]] }
        it 'does not generate output' do
          write_csv
          output = File.read(file_path)
          expect(output).to eq ''
        end
      end
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
        let(:options) { {map_headers: { name: "Person", country: "Country"} } }

        it 'writes the given headers and data correctly and does not auto-discover headers' do
          create_csv_file

          output = File.read(file_path)

          expect(output).to include("Person,Country#{row_sep}")
          expect(output).to include("John,#{row_sep}")
          expect(output).to include("Jane,USA#{row_sep}")
          expect(output).to include("Mike,#{row_sep}")
          expect(output).to include("Alex,USA#{row_sep}")
        end
      end

      context "when map_headers is given explicitly" do
        let(:options) do
          {
            map_headers: { name: "Person", country: "Country" },
            discover_headers: true # still auto-discover other headers
          }
        end

        it 'writes the given headers and data correctly and auto-discovers all headers' do
          create_csv_file

          output = File.read(file_path)

          expect(output).to include("Person,Country,age,city,state#{row_sep}")
          expect(output).to include("John,,30,New York#{row_sep}")
          expect(output).to include("Jane,USA,25,#{row_sep}")
          expect(output).to include("Mike,,35,Chicago,IL#{row_sep}")
          expect(output).to include("Alex,USA,,,#{row_sep}")
        end
      end
    end

    context 'when quoted CSV fields' do
      describe 'when quote_char' do
        let(:options) { {} }
        let(:data_batches) do
          [
            { name: 'John', age: 30, city: 'New "York' },
          ]
        end

        it 'auto-escapes quote_char' do
          create_csv_file

          output = File.read(file_path)
          expect(output).to include("name,age,city#{row_sep}")
          expect(output).to include('John,30,"New ""York"')
        end
      end

      describe 'when special_char row_sep' do
        let(:options) { {} }
        let(:data_batches) do
          [
            { name: 'John', age: 30, city: "New \nYork" },
          ]
        end

        it 'auto-escapes row_sep' do
          create_csv_file

          output = File.read(file_path)
          expect(output).to include("name,age,city#{row_sep}")
          expect(output).to match(/John,30,"New \nYork"/)
        end
      end

      describe 'when comma' do
        let(:options) { {} }
        let(:data_batches) do
          [
            { name: 'John', age: 30, city: "New York, New York" },
          ]
        end

        it 'auto-escapes comma' do
          create_csv_file

          output = File.read(file_path)
          expect(output).to include("name,age,city#{row_sep}")
          expect(output).to match(/John,30,"New York, New York"/)
        end
      end
    end
  end

  context 'when configuring headers' do
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

    context 'when headers are arbitrarily mapped' do
      let(:options) do
        {
          map_headers: {
            name: 'Voller Name',
            age: 'Alter',
            city: 'Stadt',
            state: 'Land',
            country: 'Staat',
          }
        }
      end

      it 'writes the mapped headers and data in the correct order' do
        create_csv_file

        output = File.read(file_path)

        expect(output).to include("Voller Name,Alter,Stadt,Land,Staat#{row_sep}")
        expect(output).to include("John,30,New York,,#{row_sep}")
        expect(output).to include("Jane,25,,,USA#{row_sep}")
        expect(output).to include("Mike,35,Chicago,IL,#{row_sep}")
        expect(output).to include("Alex,,,,USA#{row_sep}")
      end
    end

    context 'when header_converter is used' do
      let(:options) do
        {
          header_converter: ->(header) { header.upcase }
        }
      end

      it 'converts all the headers to upcase' do
        create_csv_file

        output = File.read(file_path)

        expect(output).to include("NAME,AGE,CITY,COUNTRY,STATE#{row_sep}")
        expect(output).to include("John,30,New York#{row_sep}")
        expect(output).to include("Jane,25,,USA#{row_sep}")
        expect(output).to include("Mike,35,Chicago,,IL#{row_sep}")
        expect(output).to include("Alex,,,USA,#{row_sep}")
      end
    end

    context 'when automatic header discovery is disabled' do
      context 'when we give explicit list of headers' do
        let(:options) do
          {
            headers: [:name, :city, :state] # giving an explicit headers list will disable header discovery
          }
        end

        it 'limits the CSV file to only the given headers' do
          create_csv_file

          output = File.read(file_path)

          expect(output).to include("name,city,state#{row_sep}")
          expect(output).to include("John,New York,#{row_sep}")
          expect(output).to include("Jane,,#{row_sep}")
          expect(output).to include("Mike,Chicago,IL#{row_sep}")
          expect(output).to include("Alex,,#{row_sep}")
        end
      end

      # NOTE:
      #  * setting `discover_headers: false` is implicit when setting :headers or :map_headers
      #  * that's why it does not make sense to set it manually to `false`.
      #  * if you want to turn off header discovery, just provide one of those two options
      #
      context 'when we explicitly disable header discovery, but do not provide headers' do
        let(:options) do
          { discover_headers: false } # THIS DOES NOT MAKE SENSE without providing :headers or :map_headers
        end

        it 'limits the CSV file to only the given headers' do
          create_csv_file

          output = File.read(file_path)
          expect(output).to eq '' # because it turns off header discovery and no headers provided
        end
      end
    end

    context 'when quoted headers' do
      let(:data) do
        { name: 'John', age: 30, city: 'New York' }
      end

      context 'when force_quotes is true' do
        let(:options) { {force_quotes: true} }

        it 'quotes all the headers and data fields' do
          writer = SmarterCSV::Writer.new(file_path, options)
          writer << data
          writer.finalize
          output = File.read(file_path)

          expect(output).to include("\"name\",\"age\",\"city\"#{row_sep}")
          expect(output).to include("\"John\",\"30\",\"New York\"#{row_sep}")
        end
      end

      context 'when force_quotes is true, even with auto-quoting disabled' do
        let(:options) do
          {
            force_quotes: true,
            disable_auto_quoting: true, # works even then
          }
        end

        it 'quotes all the headers and data fields' do
          writer = SmarterCSV::Writer.new(file_path, options)
          writer << data
          writer.finalize
          output = File.read(file_path)

          expect(output).to include("\"name\",\"age\",\"city\"#{row_sep}")
          expect(output).to include("\"John\",\"30\",\"New York\"#{row_sep}")
        end
      end

      context 'when quote_headers is true' do
        let(:options) { {quote_headers: true} }

        it 'quotes all the headers correctly, but not the data' do
          writer = SmarterCSV::Writer.new(file_path, options)
          writer << data
          writer.finalize
          output = File.read(file_path)

          expect(output).to include("\"name\",\"age\",\"city\"#{row_sep}")
          expect(output).to include("John,30,New York#{row_sep}")
        end
      end

      context 'when problematic headers are given' do
        let(:options) do
          {
            map_headers: {
              name: "last, first",      # commas / @col_sep in header
              age: '"real" age',        # double-quotes / @quote_char in header
              city: "two line\nheader", # line breaks / @row_sep in header
            }
          }
        end

        it 'correctly quotes all problematic headers, but not the data' do
          writer = SmarterCSV::Writer.new(file_path, options)
          writer << data
          writer.finalize
          output = File.read(file_path)

          expect(output).to include("\"last, first\"")
          expect(output).to include("\"\"\"real\"\" age\"")
          expect(output).to include("\"two line\nheader\"#{row_sep}")
          expect(output).to include("John,30,New York#{row_sep}")
        end
      end
    end
  end

  context 'Value Converters' do
    let(:options) do
      {
        value_converters: {
          active: ->(v) { v ? 'YES' : 'NO' },
        }
      }
    end

    it 'applies value converters to matching keys' do
      writer = SmarterCSV::Writer.new(file_path, options)
      writer << { name: 'Alice', age: 42, active: true, balance: 234.235 }
      writer.finalize

      output = File.read(file_path)
      expect(output).to include("name,age,active,balance#{row_sep}")
      expect(output).to include("Alice,42,YES,234.235#{row_sep}")
    end

    describe 'when doing advanced mapping' do
      let(:options) do
        {
          quote_headers: true,
          disable_auto_quoting: true, # ⚠️ Important: turn off auto-quoting because we're messing with it below
          value_converters: {
            active: ->(v) { v ? '✅' : '❌' },
            balance: ->(v) do
              case v
              when Float
                '$%.2f' % v.round(2)
              when Integer
                "$#{v}"
              else
                v.to_s
              end
            end,
            _all: ->(_k, v) { v.is_a?(String) ? "\"#{v}\"" : v } # only double-quote string fields
          }
        }
      end
      it 'applies all mappings in the correct order' do
        writer = SmarterCSV::Writer.new(file_path, options)
        writer << { name: 'Alice', age: 42, active: true, balance: 234.235 }
        writer << { name: 'Joe', age: 53, active: false, balance: 32_100 }
        writer.finalize

        output = File.read(file_path)
        expect(output).to include("\"name\",\"age\",\"active\",\"balance\"#{row_sep}")
        expect(output).to include("\"Alice\",42,\"✅\",\"$234.24\"#{row_sep}")
        expect(output).to include("\"Joe\",53,\"❌\",\"$32100\"#{row_sep}")
      end
    end

    it 'uses default serialization for fields without a converter' do
      partial_options = {
        headers: [:name, :age, :active],
        value_converters: {
          age: ->(v) { v.to_s }
        }
      }

      writer = SmarterCSV::Writer.new(file_path, partial_options)
      writer << { name: 'Bob', age: 50, active: false }
      writer.finalize

      output = File.read(file_path)
      expect(output).to include("Bob,50,false#{row_sep}")
    end

    it 'handles rows where only some fields use converters' do
      partial_options = {
        headers: [:name, :age, :active],
        value_converters: {
          active: ->(v) { v ? 'True' : 'False' }
        }
      }

      writer = SmarterCSV::Writer.new(file_path, partial_options)
      writer << { name: 'Charlie', age: 29, active: true }
      writer.finalize

      output = File.read(file_path)
      expect(output).to include("Charlie,29,True#{row_sep}")
    end
  end
end
