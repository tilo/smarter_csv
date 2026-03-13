# frozen_string_literal: true

RSpec.describe 'SmarterCSV.parse' do
  let(:csv_string) { "name,age\nAlice,30\nBob,25\n" }

  it 'parses a CSV string and returns an array of hashes' do
    data = SmarterCSV.parse(csv_string)
    expect(data).to eq([{name: 'Alice', age: 30}, {name: 'Bob', age: 25}])
  end

  it 'accepts options' do
    data = SmarterCSV.parse(csv_string, convert_values_to_numeric: false)
    expect(data.first[:age]).to eq('30')
  end

  it 'accepts a block and yields each row' do
    rows = []
    SmarterCSV.parse(csv_string) { |chunk| rows.concat(chunk) }
    expect(rows.size).to eq 2
    expect(rows.first).to eq({name: 'Alice', age: 30})
  end

  it 'is equivalent to SmarterCSV.process(StringIO.new(string))' do
    via_parse   = SmarterCSV.parse(csv_string)
    via_process = SmarterCSV.process(StringIO.new(csv_string))
    expect(via_parse).to eq(via_process)
  end
end
