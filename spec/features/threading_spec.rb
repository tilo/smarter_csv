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

  it 'at least returns the right number of results from each thread' do
    data = correct_sizes.keys.map do |name|
      Thread.new { [name, SmarterCSV.process("#{fixture_path}/#{name}")] }
    end.map(&:value)

    expect(data.size).to eq(4)
    data.each { |d|
      expect(d[1].size).to eq(correct_sizes[d[0]])
    }
  end
end
