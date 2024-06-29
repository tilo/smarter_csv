# frozen_string_literal: true

RSpec.describe SmarterCSV::Generator do
  let(:file_path) { 'test_output.csv' }

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
    let(:options) { { headers: %w[name age city] } }

    it 'writes the given headers and data correctly' do
      generator = SmarterCSV::Generator.new(file_path, options)
      data_batches.each { |batch| generator.append(batch) }
      generator.finalize

      output = File.read(file_path)
      expect(output).to include("name,age,city,country,state\n")
      expect(output).to include("John,30,New York,,\n")
      expect(output).to include("Jane,25,,USA,\n")
      expect(output).to include("Mike,35,Chicago,,IL\n")
    end
  end

  context 'when headers are automatically discovered' do
    it 'writes the discovered headers and data correctly' do
      generator = SmarterCSV::Generator.new(file_path)
      data_batches.each { |batch| generator.append(batch) }
      generator.finalize

      output = File.read(file_path)
      expect(output).to include("name,age,city,country,state\n")
      expect(output).to include("John,30,New York,,\n")
      expect(output).to include("Jane,25,,USA,\n")
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
      generator = SmarterCSV::Generator.new(file_path, options)
      data_batches.each { |batch| generator.append(batch) }
      generator.finalize

      output = File.read(file_path)
      expect(output).to include("Full Name,Age,City,Country,State\n")
      expect(output).to include("John,30,New York,,\n")
      expect(output).to include("Jane,25,,USA,\n")
      expect(output).to include("Mike,35,Chicago,,IL\n")
    end
  end
end
