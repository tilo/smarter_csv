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

    # --- Optimization #10: String#index skip-ahead inside quoted fields ---

    it 'correctly parses a long quoted field (skip-ahead optimization)' do
      long_content = 'x' * 10_000
      options = {col_sep: ',', quote_char: '"', quote_escaping: :double_quotes,
                 strip_whitespace: false, row_sep: "\n", quote_boundary: :standard}
      elements, size = reader.send(:parse_csv_line_ruby, "\"#{long_content}\",after", options)
      expect(size).to eq 2
      expect(elements[0]).to eq long_content
      expect(elements[1]).to eq 'after'
    end

    it 'handles doubled quotes ("") inside a long quoted field (skip-ahead + cleanup_quotes)' do
      # Each segment: 100 x-chars followed by "" (doubled quote).
      # After cleanup_quotes, "" becomes a single ".
      segment   = 'x' * 100 + '""'
      raw_inner = segment * 10                       # 1000 x-chars + 20 doubled quotes
      expected  = raw_inner.gsub('""', '"')
      options = {col_sep: ',', quote_char: '"', quote_escaping: :double_quotes,
                 strip_whitespace: false, row_sep: "\n", quote_boundary: :standard}
      elements, size = reader.send(:parse_csv_line_ruby, "\"#{raw_inner}\"", options)
      expect(size).to eq 1
      expect(elements[0]).to eq expected
    end

    it 'returns -1 (unclosed) for a long quoted field with no closing quote (skip-ahead nil branch)' do
      long_content = 'y' * 5_000
      options = {col_sep: ',', quote_char: '"', quote_escaping: :double_quotes,
                 strip_whitespace: false, row_sep: "\n", quote_boundary: :standard}
      elements, size = reader.send(:parse_csv_line_ruby, "\"#{long_content}", options)
      expect(size).to eq(-1)
    end

    it 'skip-ahead works with multi-char col_sep and long quoted field' do
      long_content = 'z' * 1_000
      options = {col_sep: '||', quote_char: '"', quote_escaping: :double_quotes,
                 strip_whitespace: false, row_sep: "\n", quote_boundary: :standard}
      elements, size = reader.send(:parse_csv_line_ruby, "\"#{long_content}\"||after", options)
      expect(size).to eq 2
      expect(elements[0]).to eq long_content
      expect(elements[1]).to eq 'after'
    end

    it 'returns -1 for unclosed quote with multi-char col_sep (skip-ahead nil branch, multi-char path)' do
      options = {col_sep: '||', quote_char: '"', quote_escaping: :double_quotes,
                 strip_whitespace: false, row_sep: "\n", quote_boundary: :standard}
      elements, size = reader.send(:parse_csv_line_ruby, '"unclosed||field', options)
      expect(size).to eq(-1)
    end
  end

  describe 'parse_line_to_hash_ruby — Optimization #11 (direct hash construction)' do
    let(:reader) { SmarterCSV::Reader.new("#{fixture_path}/basic.csv", {acceleration: false}) }

    it 'strips whitespace in the unquoted direct path when strip_whitespace: true' do
      headers = [:a, :b, :c]
      options = {col_sep: ',', quote_char: '"', quote_escaping: :double_quotes, row_sep: "\n",
                 strip_whitespace: true, remove_empty_hashes: false, remove_empty_values: true,
                 missing_header_prefix: 'column_'}
      result, size = reader.send(:parse_line_to_hash_ruby, " hello , world , ! ", headers, options)
      expect(size).to eq 3
      expect(result[:a]).to eq 'hello'
      expect(result[:b]).to eq 'world'
      expect(result[:c]).to eq '!'
    end

    it 'does not strip whitespace in the unquoted direct path when strip_whitespace: false' do
      headers = [:a, :b]
      options = {col_sep: ',', quote_char: '"', quote_escaping: :double_quotes, row_sep: "\n",
                 strip_whitespace: false, remove_empty_hashes: false, remove_empty_values: true,
                 missing_header_prefix: 'column_'}
      result, _size = reader.send(:parse_line_to_hash_ruby, " hello , world ", headers, options)
      expect(result[:a]).to eq ' hello '
      expect(result[:b]).to eq ' world '
    end

    it 'uses the quoted path (not direct path) when col_sep is a space' do
      headers = [:a, :b]
      options = {col_sep: ' ', quote_char: '"', quote_escaping: :double_quotes, row_sep: "\n",
                 strip_whitespace: false, remove_empty_hashes: false, remove_empty_values: true,
                 missing_header_prefix: 'column_'}
      # Space-sep lines go through parse_csv_line_ruby (not String#split direct path)
      result, size = reader.send(:parse_line_to_hash_ruby, 'foo bar', headers, options)
      expect(size).to eq 2
      expect(result[:a]).to eq 'foo'
      expect(result[:b]).to eq 'bar'
    end

    it 'returns nil for all-blank unquoted row when remove_empty_hashes: true (direct path)' do
      headers = [:a, :b]
      options = {col_sep: ',', quote_char: '"', quote_escaping: :double_quotes, row_sep: "\n",
                 strip_whitespace: false, remove_empty_hashes: true, remove_empty_values: true,
                 missing_header_prefix: 'column_'}
      result, _size = reader.send(:parse_line_to_hash_ruby, ',', headers, options)
      expect(result).to be_nil
    end

    it 'fills missing columns with nil in the quoted path when remove_empty_values: false' do
      # A line with a quote character goes through the quoted path (not the direct unquoted path).
      # When the row has fewer fields than headers, nil-padding must still apply.
      headers = [:a, :b, :c, :d]
      options = {col_sep: ',', quote_char: '"', quote_escaping: :double_quotes, row_sep: "\n",
                 strip_whitespace: false, remove_empty_hashes: false, remove_empty_values: false,
                 missing_header_prefix: 'column_', quote_boundary: :standard}
      result, size = reader.send(:parse_line_to_hash_ruby, '"x",y', headers, options, true)
      expect(size).to eq 2
      expect(result[:a]).to eq 'x'
      expect(result[:b]).to eq 'y'
      expect(result[:c]).to be_nil
      expect(result[:d]).to be_nil
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
    # Line must have a quote so parse_line_to_hash_ruby takes the quoted path
    # (which calls parse_csv_line_ruby). Unquoted lines now use the direct-split
    # path and never call parse_csv_line_ruby, so the mock would never fire.
    hash, size = reader.send(:parse_line_to_hash_auto, '"val\\",c', headers, auto_opts)
    expect(size).to eq 2
  end
end

# -----------------------------------------------------------------------
# Tests targeting lines 334-336, 353-355:
#   BYTEINDEX_AVAILABLE else-branch — the inline getbyte scan used when
#   String#byteindex is unavailable (Ruby < 3.2). On Ruby 3.2+ the constant
#   is true, so the else branch is never reached in normal runs.
#   stub_const forces the false path so both branches are exercised.
# -----------------------------------------------------------------------
describe 'parse_csv_line_ruby BYTEINDEX_AVAILABLE: false fallback (lines 334-336, 353-355)' do
  let(:reader) { SmarterCSV::Reader.new("#{fixture_path}/basic.csv", {acceleration: false}) }

  before { stub_const('SmarterCSV::Parser::BYTEINDEX_AVAILABLE', false) }

  # Opt #10 else-branch (lines 334-336): getbyte scan inside a quoted field.
  # Triggered when in_quotes && !allow_escaped_quotes in the col_sep_size==1 loop.

  it 'parses a quoted field using inline getbyte scan when byteindex unavailable (line 334-336, found)' do
    options = {col_sep: ',', quote_char: '"', quote_escaping: :double_quotes,
               strip_whitespace: false, row_sep: "\n", quote_boundary: :standard}
    # '"hello",world' — Opt #10 fires at i=1 (inside "hello"); getbyte scan
    # advances through 'h','e','l','l','o' until it finds the closing '"' at i=6.
    elements, size = reader.send(:parse_csv_line_ruby, '"hello",world', options)
    expect(size).to eq 2
    expect(elements[0]).to eq 'hello'
    expect(elements[1]).to eq 'world'
  end

  it 'returns -1 for unclosed quoted field via inline getbyte scan (line 336 nil branch)' do
    options = {col_sep: ',', quote_char: '"', quote_escaping: :double_quotes,
               strip_whitespace: false, row_sep: "\n", quote_boundary: :standard}
    # '"unclosed' — getbyte scan exhausts the string without finding a closing '"' → nil.
    elements, size = reader.send(:parse_csv_line_ruby, '"unclosed', options)
    expect(size).to eq(-1)
    expect(elements).to eq([])
  end

  # Opt #12 else-branch (lines 353-355): getbyte scan for the next col_sep.
  # Triggered when quote_boundary_standard && field_started && !in_quotes.
  # A mixed line (quoted field then unquoted fields) causes field_started=true
  # after the first field closes, so Opt #12 fires on subsequent fields.

  it 'parses unquoted fields via inline getbyte col_sep scan when byteindex unavailable (lines 353-355, found)' do
    options = {col_sep: ',', quote_char: '"', quote_escaping: :double_quotes,
               strip_whitespace: false, row_sep: "\n", quote_boundary: :standard}
    # '"q",a,b' — after the quoted 'q' field closes, 'a' sets field_started; Opt #12
    # getbyte-scans for ',' and finds it at the next position (line 355 returns j).
    elements, size = reader.send(:parse_csv_line_ruby, '"q",a,b', options)
    expect(size).to eq 3
    expect(elements).to eq ['q', 'a', 'b']
  end

  it 'returns the last field when no col_sep found in getbyte col_sep scan (line 355 nil branch)' do
    options = {col_sep: ',', quote_char: '"', quote_escaping: :double_quotes,
               strip_whitespace: false, row_sep: "\n", quote_boundary: :standard}
    # '"q",lastfield' — Opt #12 getbyte-scans from position 5 to end; no ',' found,
    # scan exhausts the string and returns nil → break, trailing field extracted.
    elements, size = reader.send(:parse_csv_line_ruby, '"q",lastfield', options)
    expect(size).to eq 2
    expect(elements).to eq ['q', 'lastfield']
  end
end

# -----------------------------------------------------------------------
# Tests targeting lines 461-462:
#   Multi-char col_sep path + quote_escaping: :backslash + field that starts
#   with a backslash. Existing tests use double_quotes escaping (allow_escaped_quotes
#   is false), so lines 461-462 are never reached in those tests.
# -----------------------------------------------------------------------
describe 'parse_csv_line_ruby — multi-char col_sep + backslash at field start (lines 461-462)' do
  let(:reader) { SmarterCSV::Reader.new("#{fixture_path}/basic.csv", {acceleration: false}) }

  it 'increments backslash_count and sets field_started for backslash at field boundary (lines 461-462)' do
    options = {col_sep: '||', quote_char: '"', quote_escaping: :backslash,
               strip_whitespace: false, row_sep: "\n", quote_boundary: :standard}
    # '\\"x"||b' chars: \, ", x, ", |, |, b
    # The field starts with \ (not field_started yet), so Opt #12 cannot pre-empt.
    # line[0] == '\\' → line 461 fires (backslash_count += 1);
    # line 462 fires (field_started = true since !in_quotes and quote_boundary_standard).
    elements, size = reader.send(:parse_csv_line_ruby, '\\"x"||b', options)
    expect(size).to eq 2
    expect(elements[1]).to eq 'b'
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
