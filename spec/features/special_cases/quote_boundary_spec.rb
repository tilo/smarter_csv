# frozen_string_literal: true

require 'stringio'

fixture_path = 'spec/fixtures'

# Tests for quote_boundary: :standard option.
#
# In :legacy mode (default), any " character toggles in/out of quoted state.
# In :standard mode, a quote only opens a quoted field when it appears at the
# start of the field (before any content). Mid-field quotes are treated as
# literal characters. Closing a quoted field (any " while in_quotes) is always
# valid in standard mode.
#
# This prevents mid-field quotes like b"bb from incorrectly entering quoted
# mode and garbling the parse.

[true, false].each do |bool|
  describe "quote_boundary option with#{bool ? ' C-' : 'out '}acceleration" do
    let(:base_options) { { acceleration: bool } }

    # ----------------------------------------------------------------
    # :legacy mode (default) — baseline, existing behavior preserved
    # ----------------------------------------------------------------
    describe "quote_boundary: :legacy (default)" do
      it ':standard is the default value' do
        reader = SmarterCSV::Reader.new(StringIO.new("a,b\n1,2\n"), base_options)
        expect(reader.options[:quote_boundary]).to eq(:standard)
      end

      # Exercises reader.rb detect_multiline else-branch:
      # quote_boundary: :legacy + explicit quote_escaping (not :auto) → count_quote_chars path
      it 'uses count_quote_chars for multiline detection with explicit quote_escaping' do
        # A properly quoted multiline field — should stitch correctly
        reader = SmarterCSV::Reader.new(
          StringIO.new("col\n\"line one\nline two\"\n"),
          base_options.merge(quote_boundary: :legacy, quote_escaping: :double_quotes)
        )
        data = reader.process
        expect(data[0]).to eq({ col: "line one\nline two" })
      end

      it 'parses a properly quoted field' do
        reader = SmarterCSV::Reader.new(
          StringIO.new("first,second\n\"hello, world\",other\n"),
          base_options
        )
        data = reader.process
        expect(data.size).to eq(1)
        expect(data[0]).to eq({ first: "hello, world", second: "other" })
      end

      it 'parses RFC doubled quotes' do
        reader = SmarterCSV::Reader.new(
          StringIO.new("name\n\"he said \"\"hi\"\"\"\n"),
          base_options
        )
        data = reader.process
        expect(data[0]).to eq({ name: 'he said "hi"' })
      end
    end

    # ----------------------------------------------------------------
    # :standard mode — mid-field quotes are literals
    # ----------------------------------------------------------------
    describe "quote_boundary: :standard" do
      let(:standard_options) { base_options.merge(quote_boundary: :standard) }

      # --- Mid-field quote (the main use-case) ---
      it 'treats a mid-field quote as a literal character' do
        # aaa,b"bb,ccc — the " in "b"bb" is not at field start, so literal
        reader = SmarterCSV::Reader.new(
          "#{fixture_path}/unquoted_quote_midfield.csv",
          standard_options
        )
        data = reader.process
        expect(data.size).to eq(1)
        expect(data[0]).to eq({ first: "aaa", second: 'b"bb', third: "ccc" })
      end

      it 'treats a mid-field quote as literal via StringIO' do
        reader = SmarterCSV::Reader.new(
          StringIO.new("col\nabc\"def\n"),
          standard_options
        )
        data = reader.process
        expect(data[0]).to eq({ col: 'abc"def' })
      end

      # --- Quote at field start (normal quoting still works) ---
      it 'enters quoted mode when quote is at field start' do
        reader = SmarterCSV::Reader.new(
          StringIO.new("first,second\n\"hello, world\",other\n"),
          standard_options
        )
        data = reader.process
        expect(data.size).to eq(1)
        expect(data[0]).to eq({ first: "hello, world", second: "other" })
      end

      it 'parses RFC doubled quotes inside a properly opened quoted field' do
        reader = SmarterCSV::Reader.new(
          StringIO.new("name\n\"he said \"\"hi\"\"\"\n"),
          standard_options
        )
        data = reader.process
        expect(data[0]).to eq({ name: 'he said "hi"' })
      end

      it 'handles a quoted field at the end of a line' do
        reader = SmarterCSV::Reader.new(
          StringIO.new("first,second\naaa,\"bbb\"\n"),
          standard_options
        )
        data = reader.process
        expect(data[0]).to eq({ first: "aaa", second: "bbb" })
      end

      # --- Mixed: properly quoted + mid-field literal quote in same line ---
      it 'handles a mix of properly quoted and literal-quote fields' do
        # aaa,"bb,bb",c"c
        # field 1: aaa (plain)
        # field 2: "bb,bb" (properly quoted, separator inside)
        # field 3: c"c (literal quote mid-field)
        reader = SmarterCSV::Reader.new(
          StringIO.new("first,second,third\naaa,\"bb,bb\",c\"c\n"),
          standard_options
        )
        data = reader.process
        expect(data.size).to eq(1)
        expect(data[0]).to eq({ first: "aaa", second: "bb,bb", third: 'c"c' })
      end

      # --- Quote-only field ---
      it 'treats a standalone quote as a literal when not at field start boundary' do
        # col," , " — second field starts with quote, contains comma, properly quoted
        reader = SmarterCSV::Reader.new(
          StringIO.new("col1,col2\nval,\" , \"\n"),
          standard_options.merge(strip_whitespace: false)
        )
        data = reader.process
        expect(data[0]).to eq({ col1: "val", col2: " , " })
      end

      # --- Multiple fields with leading-whitespace awareness ---
      it 'still opens quoted mode after col_sep even with leading whitespace stripped' do
        # With strip_whitespace: true (default), leading spaces before quote
        # should not prevent field_started from being false at a true boundary.
        # The strip logic: space/tab at field start doesn't set field_started.
        reader = SmarterCSV::Reader.new(
          StringIO.new("a,b\n1,\"two\"\n"),
          standard_options
        )
        data = reader.process
        expect(data[0]).to eq({ a: 1, b: "two" })
      end

      # --- Multiline detection is also boundary-aware ---
      # A mid-field quote must NOT trigger multiline stitching.
      it 'does not trigger multiline stitching for a mid-field quote' do
        # In :legacy mode, b"bb would have an odd quote count → multiline stitching.
        # In :standard mode, that quote is a literal → even boundary-quote count → no stitching.
        csv_data = "first,second,third\naaa,b\"bb,ccc\n"
        reader = SmarterCSV::Reader.new(StringIO.new(csv_data), standard_options)
        # Should parse cleanly as 1 data row, not stitch lines together
        data = reader.process
        expect(data.size).to eq(1)
        expect(data[0][:second]).to eq('b"bb')
      end

      # --- Multi-char col_sep with :standard mode ---
      # Exercises the multi-char separator slow path (parser.rb lines 285-312)
      context "with a multi-char col_sep" do
        let(:multi_sep_options) { standard_options.merge(col_sep: '|~', row_sep: "\n") }

        it 'treats mid-field quote as literal with multi-char separator' do
          reader = SmarterCSV::Reader.new(
            StringIO.new("first|~second|~third\naaa|~b\"bb|~ccc\n"),
            multi_sep_options
          )
          data = reader.process
          expect(data[0]).to eq({ first: "aaa", second: 'b"bb', third: "ccc" })
        end

        it 'parses a properly quoted field containing the separator with multi-char col_sep' do
          reader = SmarterCSV::Reader.new(
            StringIO.new("first|~second\naaa|~\"hel|~lo\"\n"),
            multi_sep_options
          )
          data = reader.process
          expect(data[0]).to eq({ first: "aaa", second: "hel|~lo" })
        end

        it 'handles opening quote at field boundary with multi-char separator' do
          reader = SmarterCSV::Reader.new(
            StringIO.new("a|~b\n1|~\"two\"\n"),
            multi_sep_options
          )
          data = reader.process
          expect(data[0]).to eq({ a: 1, b: "two" })
        end

        it 'tracks non-quote field content with multi-char separator (field_started)' do
          # Ensures a quote after other content is treated as literal
          reader = SmarterCSV::Reader.new(
            StringIO.new("col\nabc\"def\n"),
            multi_sep_options
          )
          data = reader.process
          expect(data[0]).to eq({ col: 'abc"def' })
        end

        it 'handles backslash in unquoted field with multi-char separator in :standard mode' do
          # No " in line → has_quotes=false → fast-split path (not the character loop).
          # Tests that backslash is returned as-is when split is used directly.
          reader = SmarterCSV::Reader.new(
            StringIO.new("col\nabc\\def\n"),
            multi_sep_options.merge(quote_escaping: :backslash)
          )
          data = reader.process
          expect(data[0]).to eq({ col: 'abc\def' })
        end

        it 'increments backslash_count in the character loop with multi-char separator' do
          # Line contains a " (so has_quotes=true → character-by-character loop) AND a backslash.
          # The backslash in the first field exercises parser.rb:285-286:
          # backslash_count increment and field_started assignment in the multi-char path.
          reader = SmarterCSV::Reader.new(
            StringIO.new("col1|~col2\nabc\\|~\"hello\"\n"),
            multi_sep_options.merge(quote_escaping: :backslash)
          )
          data = reader.process
          expect(data[0]).to eq({ col1: "abc\\", col2: 'hello' })
        end

        it 'parses RFC doubled quotes inside a quoted field with multi-char separator' do
          # RFC 4180: "he said ""hi""" encodes the value: he said "hi"
          # The doubled "" inside the quoted field causes the closing-quote check to
          # evaluate the row_sep condition (parser.rb:296) and find it false,
          # correctly treating "" as a literal quote rather than closing the field.
          reader = SmarterCSV::Reader.new(
            StringIO.new("name|~val\n\"he said \"\"hi\"\"\"|~25\n"),
            multi_sep_options
          )
          data = reader.process
          expect(data[0]).to eq({ name: 'he said "hi"', val: 25 })
        end
      end

      # --- Comparison: same data behaves differently in :legacy vs :standard ---
      context "behavioral difference between :legacy and :standard" do
        it ':legacy mode — quote mid-field toggles in_quotes' do
          # In legacy mode "b"bb" would enter quoted mode at the second "b
          # Wait — actually "b"bb":
          # b → not a quote, field_started doesn't apply in legacy
          # " → in_quotes = true (legacy toggles always)
          # b, b → inside quotes
          # End of field: in_quotes still true → MalformedCSV in strict legacy parse
          # OR: legacy count 1 (odd) → multiline stitch attempted → MalformedCSV
          #
          # The default quote_escaping: :auto first tries :backslash, which raises
          # MalformedCSV, then falls back to :double_quotes — which also raises here.
          # So the overall result is MalformedCSV.
          reader = SmarterCSV::Reader.new(
            StringIO.new("col\nb\"bb\n"),
            base_options.merge(quote_boundary: :legacy)
          )
          # Legacy mode: mid-field " toggles into quoted state → unclosed → MalformedCSV
          expect { reader.process }.to raise_error(SmarterCSV::MalformedCSV)
        end

        it ':standard mode — same data parses as a literal quote' do
          reader = SmarterCSV::Reader.new(
            StringIO.new("col\nb\"bb\n"),
            standard_options
          )
          data = reader.process
          expect(data[0]).to eq({ col: 'b"bb' })
        end
      end
    end

    # ----------------------------------------------------------------
    # default behavior — no explicit quote_boundary option
    # These tests use only { acceleration: bool } to confirm that
    # :standard mode is the default and handles real-world edge cases.
    # ----------------------------------------------------------------
    describe "default behavior (no explicit quote_boundary option)" do
      # Rule 1: A quote mid-field (not at field start) is a literal character
      # Input:  aaa,b"bb,ccc
      # Result: cell1=aaa, cell2=b"bb, cell3=ccc
      context "unquoted quote character mid-field" do
        let(:csv_path) { "#{fixture_path}/unquoted_quote_midfield.csv" }

        it 'treats mid-field quote as a literal character' do
          data = SmarterCSV::Reader.new(csv_path, base_options).process
          expect(data.size).to eq(1)
          expect(data[0]).to eq({ first: "aaa", second: 'b"bb', third: "ccc" })
        end
      end

      # Rules 1+2: Field starts with quote but no valid closing quote exists
      # (no " is followed by , or EOL) → unclosed quote → MalformedCSV
      # Input:  "aa"a,"bb"bb"b,ccc
      context "opening quote with no valid closing quote" do
        let(:csv_path) { "#{fixture_path}/closing_quote_non_delimiter.csv" }

        it 'raises MalformedCSV for unclosed quoted field' do
          expect { SmarterCSV::Reader.new(csv_path, base_options).process }.to raise_error(SmarterCSV::MalformedCSV)
        end
      end

      # Properly quoted field with separator inside (standard RFC 4180)
      context "properly quoted field containing separator" do
        it 'parses the quoted field correctly' do
          data = SmarterCSV::Reader.new(StringIO.new("first,second\n\"hello, world\",other\n"), base_options).process
          expect(data.size).to eq(1)
          expect(data[0]).to eq({ first: "hello, world", second: "other" })
        end
      end

      # RFC doubled quotes: "" inside quoted field represents literal "
      context "RFC doubled quotes" do
        it 'unescapes doubled quotes correctly' do
          data = SmarterCSV::Reader.new(StringIO.new("first,second\n\"he said \"\"hi\"\"\",other\n"), base_options).process
          expect(data.size).to eq(1)
          expect(data[0]).to eq({ first: 'he said "hi"', second: "other" })
        end
      end

      # Mixed: some fields properly quoted, some with literal mid-field quotes
      context "mixed quoted and unquoted fields with literal quotes" do
        it 'handles each field according to its boundary' do
          data = SmarterCSV::Reader.new(StringIO.new("first,second,third\naaa,\"bb,bb\",c\"c\n"), base_options).process
          expect(data.size).to eq(1)
          expect(data[0]).to eq({ first: "aaa", second: "bb,bb", third: 'c"c' })
        end
      end

      # Empty quoted field
      context "empty quoted field" do
        it 'returns empty string for empty quoted field' do
          data = SmarterCSV::Reader.new(StringIO.new("first,second\n\"\",other\n"), base_options).process
          expect(data.size).to eq(1)
          expect(data[0]).to eq({ second: "other" }) # empty string removed by default remove_empty_values
        end
      end

      # Quote at field start, properly closed at end of line
      context "quoted field at end of line" do
        it 'parses quoted field at end of line' do
          data = SmarterCSV::Reader.new(StringIO.new("first,second\naaa,\"bbb\"\n"), base_options).process
          expect(data.size).to eq(1)
          expect(data[0]).to eq({ first: "aaa", second: "bbb" })
        end
      end
    end
  end
end
