# frozen_string_literal: true

fixture_path = 'spec/fixtures'

describe 'chunked reading' do
  it 'loads_chunk_cornercase_csv_files' do
    6.times do |chunk_size| # test for all chunk-sizes
      options = {chunk_size: chunk_size, remove_empty_hashes: true}
      data = SmarterCSV.process("#{fixture_path}/chunk_cornercase.csv", options)
      expect(data.flatten.size).to eq 5 # end-result must always be 5 rows
    end
  end

  it 'processes chunks with a block' do
    i = 0
    n = 0
    options = {chunk_size: 2, remove_empty_hashes: true}
    SmarterCSV.process("#{fixture_path}/chunk_cornercase.csv", options) do |chunk|
      i += 1
      chunk.each do |hash|
        n += hash.values.sum
      end
    end

    expect(n).to eq 120
    expect(i).to eq 3
  end

  it 'processes blocks without chunking' do
    i = 0
    n = 0
    options = {remove_empty_hashes: true}
    SmarterCSV.process("#{fixture_path}/chunk_cornercase.csv", options) do |chunk|
      i += 1
      n += chunk.first.values.sum
    end

    expect(n).to eq 120
    expect(i).to eq 5
  end
end
