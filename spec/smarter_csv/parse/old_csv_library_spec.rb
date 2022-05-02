require 'spec_helper'

describe 'old CSV library parsing tests' do
  let(:options) { {quote_char: '"', col_sep: ","} }

  [ ["\t", ["\t"]],
    ["foo,\"\"\"\"\"\",baz", ["foo", "\"\"", "baz"]],
    ["foo,\"\"\"bar\"\"\",baz", ["foo", "\"bar\"", "baz"]],
    ["\"\"\"\n\",\"\"\"\n\"", ["\"\n", "\"\n"]],
    ["foo,\"\r\n\",baz", ["foo", "\r\n", "baz"]],
    ["\"\"", [""]],
    ["foo,\"\"\"\",baz", ["foo", "\"", "baz"]],
    ["foo,\"\r.\n\",baz", ["foo", "\r.\n", "baz"]],
    ["foo,\"\r\",baz", ["foo", "\r", "baz"]],
    ["foo,\"\",baz", ["foo", "", "baz"]],
    ["\",\"", [","]],
    ["foo", ["foo"]],
    [",,", ['', '', '']],
    [",", ['', '']],
    ["foo,\"\n\",baz", ["foo", "\n", "baz"]],
    ["foo,,baz", ["foo", '', "baz"]],
    ["\"\"\"\r\",\"\"\"\r\"", ["\"\r", "\"\r"]],
    ["\",\",\",\"", [",", ","]],
    ["foo,bar,", ["foo", "bar", '']],
    [",foo,bar", ['', "foo", "bar"]],
    ["foo,bar", ["foo", "bar"]],
    [";", [";"]],
    ["\t,\t", ["\t", "\t"]],
    ["foo,\"\r\n\r\",baz", ["foo", "\r\n\r", "baz"]],
    ["foo,\"\r\n\n\",baz", ["foo", "\r\n\n", "baz"]],
    ["foo,\"foo,bar\",baz", ["foo", "foo,bar", "baz"]],
    [";,;", [";", ";"]]
  ].each do |line, result|
    it "parses #{line}" do
      array, array_size = SmarterCSV.send(:parse, line, options)
      expect(array).to eq result
    end
  end

  [ ["foo,\"\"\"\"\"\",baz", ["foo", "\"\"", "baz"]],
    ["foo,\"\"\"bar\"\"\",baz", ["foo", "\"bar\"", "baz"]],
    ["foo,\"\r\n\",baz", ["foo", "\r\n", "baz"]],
    ["\"\"", [""]],
    ["foo,\"\"\"\",baz", ["foo", "\"", "baz"]],
    ["foo,\"\r.\n\",baz", ["foo", "\r.\n", "baz"]],
    ["foo,\"\r\",baz", ["foo", "\r", "baz"]],
    ["foo,\"\",baz", ["foo", "", "baz"]],
    ["foo", ["foo"]],
    [",,", ['', '', '']],
    [",", ['', '']],
    ["foo,\"\n\",baz", ["foo", "\n", "baz"]],
    ["foo,,baz", ["foo", '', "baz"]],
    ["foo,bar", ["foo", "bar"]],
    ["foo,\"\r\n\n\",baz", ["foo", "\r\n\n", "baz"]],
    ["foo,\"foo,bar\",baz", ["foo", "foo,bar", "baz"]]
  ].each do |line, result|
    it "parses #{line}" do
      array, array_size = SmarterCSV.send(:parse, line, options)
      expect(array).to eq result
    end
  end

  it 'mixed quotes' do
    line = %Q{Ten Thousand,10000, 2710 ,,"10,000","It's ""10 Grand"", baby",10K}
    array, array_size = SmarterCSV.send(:parse, line, options)
    expect(array).to eq ["Ten Thousand", "10000", " 2710 ", "", "10,000", "It's \"10 Grand\", baby", "10K"]
  end
end
