# frozen_string_literal: true

# Tests for Ruby fallback paths in parser.rb:
# - parse_line_to_hash_ruby
# - parse_line_to_hash_auto (including MalformedCSV fallback)
# - parse_with_auto_fallback (including MalformedCSV fallback)
# - parse_csv_line_ruby edge cases

fixture_path = 'spec/fixtures'

describe 'parser Ruby fallback paths' do
  describe 'full CSV processing with acceleration: false' do
    describe 'with quote_escaping: :auto' do
      it 'processes a basic CSV file using Ruby parser with auto quote escaping' do
        options = {acceleration: false, quote_escaping: :auto}
        data = SmarterCSV.process("#{fixture_path}/basic.csv", options)
        expect(data.size).to eq 5
        expect(data[0][:first_name]).to eq 'Dan'
      end

      it 'processes a CSV with escaped quotes using auto fallback' do
        options = {acceleration: false, quote_escaping: :auto}
        data = SmarterCSV.process("#{fixture_path}/escaped_quote_char.csv", options)
        expect(data.size).to eq 2
        expect(data[0][:escapedname]).to include('Angelos')
      end
    end

    describe 'with quote_escaping: :double_quotes' do
      it 'processes a basic CSV file using Ruby parser' do
        options = {acceleration: false, quote_escaping: :double_quotes}
        data = SmarterCSV.process("#{fixture_path}/basic.csv", options)
        expect(data.size).to eq 5
        expect(data[0][:first_name]).to eq 'Dan'
        expect(data[0][:last_name]).to eq 'McAllister'
      end
    end

    describe 'with quote_escaping: :backslash' do
      it 'processes a CSV with backslash-escaped quotes' do
        options = {acceleration: false, quote_escaping: :backslash}
        data = SmarterCSV.process("#{fixture_path}/escaped_quote_char.csv", options)
        expect(data.size).to eq 2
        expect(data[0][:content]).to eq 'Some content'
      end
    end
  end

  describe 'parse_line_to_hash_ruby edge cases' do
    let(:reader) { SmarterCSV::Reader.new("#{fixture_path}/basic.csv", {acceleration: false}) }

    it 'returns [nil, 0] for nil line' do
      headers = [:a, :b, :c]
      options = {col_sep: ',', quote_char: '"', quote_escaping: :double_quotes, row_sep: "\n",
                 strip_whitespace: false, remove_empty_hashes: true, remove_empty_values: true,
                 missing_header_prefix: 'column_'}
      result, size = reader.send(:parse_line_to_hash_ruby, nil, headers, options)
      expect(result).to be_nil
      expect(size).to eq 0
    end

    it 'returns nil hash for all-blank rows when remove_empty_hashes is true' do
      headers = [:a, :b, :c]
      options = {col_sep: ',', quote_char: '"', quote_escaping: :double_quotes, row_sep: "\n",
                 strip_whitespace: true, remove_empty_hashes: true, remove_empty_values: true,
                 missing_header_prefix: 'column_'}
      result, _size = reader.send(:parse_line_to_hash_ruby, " , , ", headers, options)
      expect(result).to be_nil
    end

    it 'assigns extra columns using missing_header_prefix' do
      headers = [:a, :b]
      options = {col_sep: ',', quote_char: '"', quote_escaping: :double_quotes, row_sep: "\n",
                 strip_whitespace: true, remove_empty_hashes: true, remove_empty_values: true,
                 missing_header_prefix: 'column_'}
      result, _size = reader.send(:parse_line_to_hash_ruby, "x,y,z", headers, options)
      expect(result[:a]).to eq 'x'
      expect(result[:b]).to eq 'y'
      expect(result[:column_3]).to eq 'z'
    end

    it 'fills missing columns with nil when remove_empty_values is false' do
      headers = [:a, :b, :c, :d]
      options = {col_sep: ',', quote_char: '"', quote_escaping: :double_quotes, row_sep: "\n",
                 strip_whitespace: false, remove_empty_hashes: false, remove_empty_values: false,
                 missing_header_prefix: 'column_'}
      result, _size = reader.send(:parse_line_to_hash_ruby, "x,y", headers, options)
      expect(result[:a]).to eq 'x'
      expect(result[:b]).to eq 'y'
      expect(result[:c]).to be_nil
      expect(result[:d]).to be_nil
    end
  end

  describe 'parse_csv_line_ruby edge cases' do
    let(:reader) { SmarterCSV::Reader.new("#{fixture_path}/basic.csv", {acceleration: false}) }

    it 'returns empty array for nil line' do
      options = {col_sep: ',', quote_char: '"', quote_escaping: :double_quotes, strip_whitespace: false}
      elements, size = reader.send(:parse_csv_line_ruby,nil, options)
      expect(elements).to eq []
      expect(size).to eq 0
    end

    it 'respects header_size limit' do
      options = {col_sep: ',', quote_char: '"', quote_escaping: :double_quotes, strip_whitespace: false}
      elements, _size = reader.send(:parse_csv_line_ruby,"a,b,c,d,e", options, 3)
      expect(elements.size).to eq 3
      expect(elements).to eq ['a', 'b', 'c']
    end

    it 'handles multi-character col_sep' do
      options = {col_sep: '||', quote_char: '"', quote_escaping: :double_quotes, strip_whitespace: false}
      elements, size = reader.send(:parse_csv_line_ruby,'a||b||c', options)
      expect(elements).to eq ['a', 'b', 'c']
      expect(size).to eq 3
    end

    it 'raises MalformedCSV for unclosed quotes' do
      options = {col_sep: ',', quote_char: '"', quote_escaping: :double_quotes, strip_whitespace: false}
      expect {
        reader.send(:parse_csv_line_ruby,'"unclosed,field', options)
      }.to raise_error(SmarterCSV::MalformedCSV, /Unclosed quoted field/)
    end
  end

  describe 'parse_with_auto_fallback rescue path (Ruby)' do
    # When quote_escaping: :auto, backslash interpretation is tried first.
    # If it raises MalformedCSV, the rescue path falls back to RFC 4180 (:double_quotes).
    # A header like "val\" fails in backslash mode (\" escapes the closing quote,
    # leaving quotes unbalanced), but succeeds in RFC 4180 where \ is literal.
    it 'falls back to RFC 4180 when backslash header interpretation fails' do
      options = {acceleration: false, quote_escaping: :auto}
      data = SmarterCSV.process("#{fixture_path}/auto_fallback_rfc.csv", options)
      expect(data.size).to eq 1
      # The header "val\" in RFC 4180 becomes val\ → normalized to :"val\\"
      expect(data[0].values).to include('test')
      expect(data[0][:other]).to eq 123
    end
  end

end
