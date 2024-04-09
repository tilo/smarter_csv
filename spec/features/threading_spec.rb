# frozen_string_literal: true

fixture_path = 'spec/fixtures'

describe 'thread safety checks' do
  let(:correct_sizes) {
    {
      'basic.csv' => 5,
      'simple_with_header.csv' => 4,
      'emoji.csv' => 3,
      'quoted.csv' => 4
    }
  }

  let(:correct_chunk_counts) {
    {
      'basic.csv' => 3,
      'simple_with_header.csv' => 2,
      'emoji.csv' => 2,
      'quoted.csv' => 2
    }
  }

  let(:correct_headers) {
    {
      'basic.csv' => [:first_name, :last_name, :dogs, :cats, :birds, :fish],
      'simple_with_header.csv' => [:user_id],
      'emoji.csv' => [:first_name, :last_name, :purchases, :score],
      'quoted.csv' => [:year, :make, :model, :description, :price]
    }
  }

  let(:correct_raw_headers) {
    {
      'basic.csv' => "First Name,Last Name,Dogs,Cats,Birds,Fish\n",
      'simple_with_header.csv' => "user_id\n",
      'emoji.csv' => "First Name|Last Name|Purchases|Score\n",
      'quoted.csv' => "Year,Make,Model,Description,Price\n"
    }
  }

  let(:correct_csv_line_counts) {
    {
      'basic.csv' => 8,
      'simple_with_header.csv' => 5,
      'emoji.csv' => 4,
      'quoted.csv' => 5
    }
  }

  it 'at least returns the right number of results from each thread' do
    data = correct_sizes.keys.map do |name|
      Thread.new { [name, SmarterCSV.process("#{fixture_path}/#{name}")] }
    end.map(&:value)

    expect(data.size).to eq(4)
    data.each { |d|
      expect(d[1].size).to eq(correct_sizes[d[0]])
    }
  end

  it 'returns the right headers for each thread' do
    50.times do
      data = correct_headers.keys.map do |name|
        Thread.new {
          rows = []
          SmarterCSV.process("#{fixture_path}/#{name}", remove_empty_values: false) { |csv| rows += csv }
          [
            name, rows
          ]
        }
      end.map(&:value)

      expect(data.size).to eq(4)
      data.each { |d|
        expect(d[1].first.keys).to eq(correct_headers[d[0]])
      }
    end
  end

  it 'returns the right headers for each thread' do
    50.times do
      data = correct_headers.keys.map do |name|
        Thread.new {
          rows = []
          SmarterCSV.process("#{fixture_path}/#{name}", remove_empty_values: false) { |csv| rows += csv }
          processed_header = SmarterCSV.headers
          [
            name, processed_header
          ]
        }
      end.map(&:value)

      expect(data.size).to eq(4)
      data.each { |d|
        expect(d[1]).to eq(correct_headers[d[0]])
      }
    end
  end

  it 'returns the right raw_headers for each thread' do
    50.times do
      data = correct_raw_headers.keys.map do |name|
        Thread.new {
          rows = []
          SmarterCSV.process("#{fixture_path}/#{name}", remove_empty_values: false) { |csv| rows += csv }
          raw_header = SmarterCSV.raw_header
          [
            name, raw_header
          ]
        }
      end.map(&:value)

      expect(data.size).to eq(4)
      data.each { |d|
        expect(d[1]).to eq(correct_raw_headers[d[0]])
      }
    end
  end

  it 'hands back the right chunk_count for each thread' do
    data = correct_chunk_counts.keys.map do |name|
      Thread.new { [name, SmarterCSV.process("#{fixture_path}/#{name}", chunk_size: 2) { |c| c }] }
    end.map(&:value)

    expect(data.size).to eq(4)
    data.each { |d|
      expect(d[1]).to eq(correct_chunk_counts[d[0]])
    }
  end

  it 'hands back the right csv_line_count for each thread' do
    data = correct_raw_headers.keys.map do |name|
      Thread.new {
        rows = []
        SmarterCSV.process("#{fixture_path}/#{name}", remove_empty_values: false) { |csv| rows += csv }
        csv_line_count = SmarterCSV.csv_line_count
        [
          name, csv_line_count
        ]
      }
    end.map(&:value)

    expect(data.size).to eq(4)
    data.each { |d|
      expect(d[1]).to eq(correct_csv_line_counts[d[0]])
    }
  end
end
