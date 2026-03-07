# frozen_string_literal: true

RSpec.describe SmarterCSV::Reader do
  let(:fixture_path) { 'spec/fixtures' }

  describe "initialize" do
    let(:filename) { "#{fixture_path}/basic.csv" }

    it "initializes the internal state" do
      reader = SmarterCSV::Reader.new(filename)
      expect(reader.chunk_count).to eq 0
      expect(reader.csv_line_count).to eq 0
      expect(reader.file_line_count).to eq 0
      expect(reader.enforce_utf8).to eq false
      expect(reader.has_rails).to eq false
      expect(reader.input).to eq filename
      expect(reader.headers).to be_nil
      expect(reader.raw_header).to be_nil
      expect(reader.headerA).to eq []
      expect(reader.warnings).to be_empty
      expect(reader.errors).to be_empty
      expect(reader.result).to eq []
      # initializes to the default options
      expect(reader.options).to eq SmarterCSV::Options::DEFAULT_OPTIONS
    end

    it "sets options" do
      reader = SmarterCSV::Reader.new(
        filename, {
          col_sep: ";", row_sep: "\r\n", quote_char: "'",
          accelleration: false,
        }
      )
      expect(reader.options[:col_sep]).to eq ';'
      expect(reader.options[:row_sep]).to eq "\r\n"
      expect(reader.options[:quote_char]).to eq "'"
      expect(reader.options[:accelleration]).to eq false
    end
  end

  # -----------------------------------------------------------------------
  # Tests targeting previously uncovered private methods in reader.rb:
  #   detect_multiline        (lines 435–449)
  #   detect_multiline_strict (lines 457–507)
  #   process_line_to_hash    (lines 536–601)
  # -----------------------------------------------------------------------

  describe 'detect_multiline (private)' do
    let(:reader) { SmarterCSV::Reader.new("#{fixture_path}/basic.csv", {acceleration: false}) }
    let(:base_opts) do
      {col_sep: ',', quote_char: '"', quote_escaping: :double_quotes,
       row_sep: "\n", strip_whitespace: false}
    end

    it 'returns false immediately when the line contains no quote character (line 436)' do
      expect(reader.send(:detect_multiline, 'no,quotes,here', base_opts)).to eq false
    end

    it 'delegates to detect_multiline_strict for balanced field when quote_boundary: :standard (lines 438–439)' do
      opts = base_opts.merge(quote_boundary: :standard)
      expect(reader.send(:detect_multiline, '"hello","world"', opts)).to eq false
    end

    it 'delegates to detect_multiline_strict for unclosed field when quote_boundary: :standard (lines 438–439)' do
      opts = base_opts.merge(quote_boundary: :standard)
      expect(reader.send(:detect_multiline, '"unclosed', opts)).to eq true
    end

    it 'returns false for :auto mode when quote count is even (lines 440–441, 446)' do
      opts = base_opts.merge(quote_escaping: :auto)
      # Two quotes (even) → escaped_count.odd? == false → not multiline
      expect(reader.send(:detect_multiline, '"hello"', opts)).to eq false
    end

    it 'returns true for :auto mode when both escaped and rfc counts are odd (lines 440–441, 446)' do
      opts = base_opts.merge(quote_escaping: :auto)
      # One unescaped quote → both counts odd → multiline
      expect(reader.send(:detect_multiline, '"unclosed', opts)).to eq true
    end

    it 'uses simple odd-count check for non-auto, non-standard mode (lines 447–448)' do
      expect(reader.send(:detect_multiline, '"unclosed', base_opts)).to eq true
      expect(reader.send(:detect_multiline, '"closed"', base_opts)).to eq false
    end
  end

  describe 'detect_multiline_strict (private)' do
    let(:reader) { SmarterCSV::Reader.new("#{fixture_path}/basic.csv", {acceleration: false}) }
    let(:base_opts) do
      {col_sep: ',', quote_char: '"', row_sep: "\n", strip_whitespace: false}
    end

    it 'returns false for balanced quoted fields across multiple columns (lines 472–491)' do
      # Exercises: col_sep reset (473–475), open at boundary (489–491), close at EOL (482, 485–486)
      expect(reader.send(:detect_multiline_strict, '"hello","world"', base_opts)).to eq false
    end

    it 'returns true for an unclosed quoted field (line 507)' do
      expect(reader.send(:detect_multiline_strict, '"unclosed', base_opts)).to eq true
    end

    it 'closes field when closing quote is immediately followed by row_sep (line 484)' do
      opts = base_opts.merge(row_sep: "\n")
      # "hello"\n — the " at position 6 is followed by \n which matches row_sep → field closes
      expect(reader.send(:detect_multiline_strict, "\"hello\"\n", opts)).to eq false
    end

    it 'sets field_started for non-whitespace character outside quotes, strip: false (line 501)' do
      # Plain unquoted text — exercises the elsif !in_quotes → strip=false → field_started=true path
      expect(reader.send(:detect_multiline_strict, 'abc,def', base_opts)).to eq false
    end

    it 'does not set field_started for whitespace before opening quote when strip: true (lines 496–498)' do
      # " "hello"" — leading space skips field_started, opening quote is at a boundary
      opts = base_opts.merge(strip_whitespace: true)
      expect(reader.send(:detect_multiline_strict, ' "hello"', opts)).to eq false
    end

    it 'sets field_started for non-whitespace character when strip: true (line 498)' do
      # 'a' triggers field_started=true via the strip branch (line[i] != ' ' and != \t)
      opts = base_opts.merge(strip_whitespace: true)
      expect(reader.send(:detect_multiline_strict, 'a,"hello"', opts)).to eq false
    end

    # ------------------------------------------------------------------
    # Byteindex fallback paths (lines 548–550, 563–565)
    #
    # When BYTEINDEX_AVAILABLE is false (older Ruby / JRuby), detect_multiline_strict
    # falls back to manual getbyte loops instead of String#byteindex.
    # Stub the constant to force the fallback on any Ruby version.
    # ------------------------------------------------------------------
    context 'byteindex fallback (BYTEINDEX_AVAILABLE: false)' do
      before { stub_const('SmarterCSV::Parser::BYTEINDEX_AVAILABLE', false) }

      # lines 548–550: getbyte loop searching for next quote byte (in_quotes = true)
      # lines 563–565: getbyte loop searching for next col_sep byte (field_started = true)
      it 'returns false for a properly closed quoted field (covers both getbyte loops)' do
        # "hello" opens (in_quotes → lines 548-550 getbyte loop finds closing quote),
        # then ,world with field_started=true (lines 563-565 getbyte loop finds next sep)
        expect(reader.send(:detect_multiline_strict, '"hello",world', base_opts)).to eq false
      end

      it 'returns true when the getbyte loop reaches end without finding a quote (lines 548-550, nil path)' do
        # No closing quote: getbyte loop exhausts the string → next_q.nil? → return true
        expect(reader.send(:detect_multiline_strict, '"unclosed', base_opts)).to eq true
      end

      it 'returns false for an unquoted line (covers lines 563-565, no col_sep found → break)' do
        # field_started=true after 'h', getbyte loop searches for col_sep byte,
        # finds none after the last field → next_sep.nil? → break; returns false
        expect(reader.send(:detect_multiline_strict, 'hello,world', base_opts)).to eq false
      end
    end

    # ------------------------------------------------------------------
    # Multi-char col_sep path (lines 603–641)
    #
    # When col_sep.size > 1, detect_multiline_strict uses a character-by-character
    # loop with substring comparison rather than the byteindex fast path.
    # ------------------------------------------------------------------
    context 'multi-char col_sep (lines 603–641)' do
      let(:multi_opts) { {col_sep: '<=>', quote_char: '"', row_sep: "\n", strip_whitespace: false} }

      # line 609: col_sep match outside quotes
      # lines 626-629: opening quote at field boundary
      # lines 616-624: closing quote followed by col_sep
      # lines 631, 637-638: non-quote char sets field_started (strip: false)
      it 'returns false for a balanced quoted field (lines 609, 616-629, 631, 638)' do
        expect(reader.send(:detect_multiline_strict, '"hello"<=>world', multi_opts)).to eq false
      end

      # lines 615-629: quote opens field; no closing quote → in_quotes still true → returns true
      it 'returns true for an unclosed quoted field with multi-char col_sep' do
        expect(reader.send(:detect_multiline_strict, '"unclosed', multi_opts)).to eq true
      end

      # lines 619: closing quote at end-of-line (next_i >= line_size branch)
      it 'returns false when closing quote is at end of line with no trailing sep' do
        expect(reader.send(:detect_multiline_strict, '"hello"', multi_opts)).to eq false
      end

      # lines 631, 633, 635: non-quote char outside quotes, strip: true
      # Space/tab must NOT set field_started; other chars must.
      it 'handles strip_whitespace: true — space skips field_started, letter sets it (line 635)' do
        opts = multi_opts.merge(strip_whitespace: true)
        # Leading space before quoted field: space must not set field_started so the
        # opening quote is still recognised as a boundary → field closes cleanly.
        expect(reader.send(:detect_multiline_strict, ' "hello"<=>world', opts)).to eq false
      end

      it 'handles unquoted fields with multi-char col_sep and strip_whitespace: false (line 638)' do
        expect(reader.send(:detect_multiline_strict, 'hello<=>world', multi_opts)).to eq false
      end

      # line 641: i += 1 at bottom of loop (incremented on every non-sep iteration)
      it 'handles multiple fields and a trailing unquoted field' do
        expect(reader.send(:detect_multiline_strict, '"a"<=>b<=>c', multi_opts)).to eq false
      end

      # line 621: closing quote followed by row_sep (not col_sep, not end-of-string)
      # Conditions: next_i < line_size (not EOL), next chars != col_sep, but == row_sep
      it 'closes field when closing quote is followed by row_sep (line 621)' do
        opts = multi_opts.merge(row_sep: "\n")
        # "hello"\n — next_i=7 is within bounds, line[7..9] != "<=>" but line[7] == "\n"
        expect(reader.send(:detect_multiline_strict, "\"hello\"\n", opts)).to eq false
      end
    end
  end

  describe 'process_line_to_hash (private)' do
    # Helper: create a reader, call process to initialise all required ivars
    # (@headers, @use_acceleration, @only_headers_set, @except_headers_set, etc.)
    # then return the fully-initialised reader for direct send(:process_line_to_hash) calls.
    def make_reader(csv_string, opts = {})
      r = SmarterCSV::Reader.new(StringIO.new(csv_string), {acceleration: false}.merge(opts))
      r.process
      r
    end

    it 'returns a hash for a normal data line (lines 540, 589, 601)' do
      r = make_reader("col1,col2\n")
      result = r.send(:process_line_to_hash, "foo,bar", r.options)
      expect(result).to eq({col1: 'foo', col2: 'bar'})
    end

    it 'returns :needs_more when the line has an unclosed quoted field (line 543)' do
      r = make_reader("col1,col2\n")
      result = r.send(:process_line_to_hash, '"unclosed', r.options)
      expect(result).to eq :needs_more
    end

    it 'extends headers for extra columns when not strict (lines 546, 552–553)' do
      r = make_reader("col1,col2\n")
      result = r.send(:process_line_to_hash, "x,y,z", r.options)
      expect(result).to include(col1: 'x', col2: 'y')
      expect(result.keys).to include(:column_3)
    end

    it 'raises HeaderSizeMismatch for extra columns when missing_headers: :raise (lines 547–548)' do
      r = make_reader("col1,col2\n", missing_headers: :raise)
      expect do
        r.send(:process_line_to_hash, "x,y,z", r.options)
      end.to raise_error(SmarterCSV::HeaderSizeMismatch)
    end

    it 'returns nil for an all-blank row (line 558)' do
      r = make_reader("col1,col2\n")
      result = r.send(:process_line_to_hash, ",", r.options)
      expect(result).to be_nil
    end

    it 'selects only specified columns when headers: { only: } is set (line 561)' do
      r = make_reader("col1,col2\n", headers: { only: [:col1] })
      result = r.send(:process_line_to_hash, "foo,bar", r.options)
      expect(result).to eq({col1: 'foo'})
      expect(result.key?(:col2)).to be false
    end

    it 'excludes specified columns when headers: { except: } is set (line 562)' do
      r = make_reader("col1,col2\n", headers: { except: [:col2] })
      result = r.send(:process_line_to_hash, "foo,bar", r.options)
      expect(result).to eq({col1: 'foo'})
      expect(result.key?(:col2)).to be false
    end

    it 'returns nil when hash is empty after transformations with remove_empty_hashes: true (line 599)' do
      # nil_values_matching: /.*/ nils every string value → empty hash → line 599 returns nil
      r = make_reader("col1,col2\n", nil_values_matching: /.*/, remove_empty_hashes: true)
      result = r.send(:process_line_to_hash, "foo,bar", r.options)
      expect(result).to be_nil
    end

    context 'acceleration path (lines 565–584)' do
      def make_accel_reader(csv_string, opts = {})
        r = SmarterCSV::Reader.new(StringIO.new(csv_string), {acceleration: true}.merge(opts))
        r.process
        r
      end

      before { skip 'C extension not available' unless SmarterCSV::Parser.respond_to?(:parse_csv_line_c) }

      it 'enters the acceleration branch and returns a valid hash (line 565)' do
        r = make_accel_reader("col1,col2\n")
        result = r.send(:process_line_to_hash, "foo,bar", r.options)
        expect(result).to be_a(Hash)
        expect(result[:col1]).to eq 'foo'
      end

      it 'executes nil/empty-key deletion when key_mapping is set (lines 568–572)' do
        # key_mapping sets @delete_nil_keys=true and @delete_empty_keys=true;
        # hash.delete(nil) and hash.delete('') execute (even if keys are absent)
        r = make_accel_reader("col1,col2\n", key_mapping: {col1: :a, col2: :b})
        result = r.send(:process_line_to_hash, "foo,bar", r.options)
        expect(result).to be_a(Hash)
        expect(result.key?(nil)).to be false
      end

      it 'nils values matching regex in the acceleration path (lines 575–578)' do
        r = make_accel_reader("col1,col2\n")
        opts = r.options.merge(nil_values_matching: /^foo$/)
        result = r.send(:process_line_to_hash, "foo,bar", opts)
        # remove_empty_values: true (default) → nil-ified value is then removed
        expect(result.key?(:col1)).to be false
        expect(result[:col2]).to eq 'bar'
      end

      it 'keeps key with nil value when remove_empty_values: false in the acceleration path (lines 590–593)' do
        r = make_accel_reader("col1,col2\n")
        opts = r.options.merge(nil_values_matching: /^foo$/, remove_empty_values: false)
        result = r.send(:process_line_to_hash, "foo,bar", opts)
        # remove_empty_values: false → key retained, value set to nil
        expect(result.key?(:col1)).to be true
        expect(result[:col1]).to be_nil
        expect(result[:col2]).to eq 'bar'
      end

      it 'applies value_converters in the acceleration path (lines 582–584)' do
        converter = double('converter')
        allow(converter).to receive(:convert).with('foo').and_return('CONVERTED')
        r = make_accel_reader("col1,col2\n")
        opts = r.options.merge(value_converters: {col1: converter})
        result = r.send(:process_line_to_hash, "foo,bar", opts)
        expect(result[:col1]).to eq 'CONVERTED'
      end
    end
  end
end
