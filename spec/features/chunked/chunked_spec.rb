# frozen_string_literal: true

fixture_path = 'spec/fixtures'

class Processor
  def self.process(item); end

  def self.process_chunk(chunk)
    chunk.each do |item|
      process(item)
    end
  end
end

describe 'chunked processing' do
  14.times do |chunk_size|
    it "loads all content from CSV file with chunk_size #{chunk_size}" do
      options = { chunk_size: chunk_size }
      data = SmarterCSV.process("#{fixture_path}/chunked.csv", options)
      expect(data.flatten.size).to eq 12 # end-result must always be 12 rows
    end
  end

  context 'process chunks with a block' do
    14.times do |chunk_size|
      it "processes with chunk size #{chunk_size}" do
        expect(Processor).to receive(:process).exactly(12).times

        options = { chunk_size: chunk_size }
        SmarterCSV.process("#{fixture_path}/chunked.csv", options) do |chunk|
          Processor.process_chunk(chunk)
        end
      end
    end
  end
end
