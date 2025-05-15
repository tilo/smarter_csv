# frozen_string_literal: true

RSpec.describe SmarterCSV::ParserC do
  let(:options) do
    { quote_char: '"', row_sep: "\n", col_sep: ',', buffer_size: 64 }
  end
  let(:source) { StringIO.new("a,b,\"c\"\"c\"\nd,e,f\n") }
  # let(:buffered_io) { SmarterCSV::BufferedIO.new(source, options[:buffer_size]) }

  subject(:parser) do
    described_class.new(source, options)
  end

  it 'parses a row with quoted and unquoted fields using C-extension' do
    fields = parser.read_row_as_fields
    expect(fields).to eq(["a", "b", 'c"c'])

    fields2 = parser.read_row_as_fields
    expect(fields2).to eq(["d", "e", "f"])
  end


end
