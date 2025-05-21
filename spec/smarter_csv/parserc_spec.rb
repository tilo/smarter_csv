# frozen_string_literal: true

require 'parser/parserc'

RSpec.describe SmarterCSV::ParserC do
  subject(:parser) do
    described_class.new(source, options)
  end

  context 'with embedded quote_char' do 
    let(:options) do
      { quote_char: '"', row_sep: "\n", col_sep: ',', buffer_size: 64 }
    end
    let(:source) { StringIO.new("a,b,\"c\"\"c\"\nd,e,f\n") }

    it 'parses a row with quoted and unquoted fields using C-extension' do
      fields = parser.read_row_as_fields
      expect(fields).to eq(["a", "b", 'c"c'])

      fields2 = parser.read_row_as_fields
      expect(fields2).to eq(["d", "e", "f"])
    end
  end

  context 'with comments in the CSV file' do 
    let(:options) do
      { quote_char: '"', row_sep: "\n", col_sep: ',', buffer_size: 64, comment_prefix: '#' }
    end
    let(:source) { './spec/fixtures/simple_w_comments.csv' }

    it 'parses simple file with comment' do 
      fields = parser.read_row_as_fields
      expect(fields).to eq(["a", "b", 'c'])
      fields2 = parser.read_row_as_fields
      expect(fields2).to eq (['1','2','3'])
    end
  end
end
