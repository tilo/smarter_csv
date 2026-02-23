# frozen_string_literal: true

# Tests for Ruby fallback paths in parser.rb:
# - parse_line_to_hash_ruby
# - parse_with_auto_fallback (including MalformedCSV fallback and backslash-in-header path)
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

    it 'returns needs-more sentinel for unclosed quotes (multiline signal)' do
      # parse_csv_line_ruby no longer raises for unclosed quotes at EOL — it returns
      # [[], -1] so the read loop can stitch the next physical line and re-parse
      # instead of performing a separate detect_multiline pre-scan pass.
      options = {col_sep: ',', quote_char: '"', quote_escaping: :double_quotes, strip_whitespace: false}
      elements, size = reader.send(:parse_csv_line_ruby, '"unclosed,field', options)
      expect(elements).to eq []
      expect(size).to eq(-1)
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

  describe 'parse_with_auto_fallback result path — parser.rb line 97' do
    # parse_with_auto_fallback reaches the final `result` return (line 97) when:
    # (a) line contains a backslash → enters the try-backslash block,
    # (b) backslash mode parses without error and returns data_size != -1.
    # A CSV header with a bare backslash (no surrounding quotes) satisfies both conditions.
    it 'returns the backslash-mode result when a header contains a backslash without quotes' do
      csv = StringIO.new("field_\\a,field_b\n1,2\n")
      data = SmarterCSV.process(csv, acceleration: false, quote_escaping: :auto)
      expect(data.size).to eq 1
      expect(data[0].values).to include(1, 2)
    end
  end

  describe 'stitch-loop RFC fallback — reader.rb line 246' do
    # In the multiline stitch while loop (Ruby path, quote_escaping: :auto):
    # after appending a continuation line, if the accumulated line still has data_size==-1
    # in backslash mode AND the accumulated line contains a backslash, we try RFC mode.
    #
    # Trigger: a quoted field that spans two physical lines where the second line ends
    # with \" — in backslash mode \" is an escaped literal (field stays open, -1),
    # but in RFC mode \ is a literal and " closes the field.
    it 'closes a multiline field via RFC fallback when continuation line has backslash-quote ending' do
      # Physical lines:
      #   col                ← header
      #   "line1             ← opens quoted field, no closing quote → initial parse: -1 (both modes)
      #   \"                 ← continuation: backslash + closing-quote + newline
      #                         backslash mode: \" is escaped literal → still open (-1)
      #                         RFC mode:       \ is literal, " closes field → data_size=1
      csv = StringIO.new("col\n\"line1\n\\\"\n")
      data = SmarterCSV.process(csv, acceleration: false, quote_escaping: :auto)
      expect(data.size).to eq 1
      expect(data[0][:col]).to eq "line1\n\\"
    end
  end

end

# -----------------------------------------------------------------------
# Tests targeting previously uncovered lines in parser.rb:
#   parse_line_to_hash        (lines 101–113)
#   parse_line_to_hash_auto   (lines 117–163)
#   parse_with_auto_fallback  rescue block (lines 71, 77)
# -----------------------------------------------------------------------
describe 'parse_line_to_hash dispatch (parser.rb lines 101–113)' do
  let(:reader) { SmarterCSV::Reader.new("#{fixture_path}/basic.csv", {acceleration: false}) }
  let(:headers) { [:col1, :col2] }
  let(:base_opts) do
    {col_sep: ',', quote_char: '"', quote_escaping: :double_quotes, row_sep: "\n",
     strip_whitespace: false, remove_empty_hashes: true, remove_empty_values: true,
     missing_header_prefix: 'column_', acceleration: false}
  end

  it 'dispatches to parse_line_to_hash_auto when quote_escaping: :auto (line 101–102)' do
    opts = base_opts.merge(quote_escaping: :auto)
    hash, size = reader.send(:parse_line_to_hash, 'foo,bar', headers, opts)
    expect(hash).to eq({col1: 'foo', col2: 'bar'})
    expect(size).to eq 2
  end

  it 'dispatches to parse_line_to_hash_ruby when not :auto, acceleration: false (lines 109–110)' do
    hash, size = reader.send(:parse_line_to_hash, 'foo,bar', headers, base_opts)
    expect(hash).to eq({col1: 'foo', col2: 'bar'})
    expect(size).to eq 2
  end
end

describe 'parse_line_to_hash_auto (parser.rb lines 117–163)' do
  let(:reader) { SmarterCSV::Reader.new("#{fixture_path}/basic.csv", {acceleration: false}) }
  let(:headers) { [:col1, :col2] }
  let(:auto_opts) do
    {col_sep: ',', quote_char: '"', quote_escaping: :auto, row_sep: "\n",
     strip_whitespace: false, remove_empty_hashes: true, remove_empty_values: true,
     missing_header_prefix: 'column_', acceleration: false}
  end

  it 'returns double-quotes result when line has no backslash (lines 143–145)' do
    # No backslash → fast-path RFC 4180 parse; also initialises @quote_escaping_* ivars (lines 117–118)
    hash, size = reader.send(:parse_line_to_hash_auto, 'foo,bar', headers, auto_opts)
    expect(hash).to eq({col1: 'foo', col2: 'bar'})
    expect(size).to eq 2
  end

  it 'returns backslash-mode result when backslash present but not before a quote (lines 149, 163)' do
    # Backslash in field value but not escaping a quote → backslash parse succeeds, data_size != -1
    hash, size = reader.send(:parse_line_to_hash_auto, 'foo\\bar,baz', headers, auto_opts)
    expect(size).to be > 0
    expect(hash).not_to be_nil
  end

  it 'falls back to RFC when backslash mode gives -1 but RFC closes the field (lines 157–159)' do
    # "val\" — backslash mode: \" escapes the closing " → unclosed (-1)
    #          RFC mode:       \ is literal, " closes field → size=1
    hash, size = reader.send(:parse_line_to_hash_auto, '"val\"', [:col1], auto_opts)
    expect(size).to eq 1
    expect(hash[:col1]).to eq 'val\\'
  end

  it 'propagates -1 when both modes agree the line is incomplete (lines 157–163)' do
    # '"unclosed' → both backslash and RFC modes see an open quoted field → propagate [nil,-1]
    hash, size = reader.send(:parse_line_to_hash_auto, '"unclosed', [:col1], auto_opts)
    expect(size).to eq(-1)
    expect(hash).to be_nil
  end

  it 'falls back to RFC when backslash parse_csv_line_ruby raises MalformedCSV (line 151)' do
    # Mock parse_csv_line_ruby to raise only when called with backslash escaping
    allow(reader).to receive(:parse_csv_line_ruby).and_wrap_original do |orig, ln, opts, *rest|
      raise SmarterCSV::MalformedCSV, "mocked" if opts[:quote_escaping] == :backslash
      orig.call(ln, opts, *rest)
    end
    hash, size = reader.send(:parse_line_to_hash_auto, 'a\\b,c', headers, auto_opts)
    expect(size).to eq 2
  end
end

describe 'parse_with_auto_fallback rescue else-branch (parser.rb lines 71, 77)' do
  # When parse_csv_line_ruby raises MalformedCSV in backslash mode with acceleration: false,
  # line 71 evaluates false (no acceleration) and line 77 executes the RFC fallback.
  let(:reader) { SmarterCSV::Reader.new("#{fixture_path}/basic.csv", {acceleration: false}) }
  let(:auto_opts) do
    {col_sep: ',', quote_char: '"', quote_escaping: :auto, row_sep: "\n",
     strip_whitespace: false, acceleration: false}
  end

  it 'evaluates line 71 as false and executes RFC fallback at line 77' do
    allow(reader).to receive(:parse_csv_line_ruby).and_wrap_original do |orig, ln, opts, *rest|
      raise SmarterCSV::MalformedCSV, "mocked" if opts[:quote_escaping] == :backslash
      orig.call(ln, opts, *rest)
    end
    # Line has a backslash so the backslash path is tried and rescued
    elements, size = reader.send(:parse_with_auto_fallback, 'a\\b,c', auto_opts)
    expect(size).to eq 2
  end
end
