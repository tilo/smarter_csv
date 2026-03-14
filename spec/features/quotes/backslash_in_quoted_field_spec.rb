# frozen_string_literal: true

# Regression test for GitHub issue #316
# https://github.com/tilo/smarter_csv/issues/316
#
# When a quoted field ends with a backslash (e.g. "X,Y\"), the parser
# incorrectly treats \" as an escaped quote and raises MalformedCSV.
# Per RFC 4180, backslash has no special meaning in CSV — only doubled
# quote characters ("") serve as escapes.
#
# The quote_escaping option controls this behavior:
#   :auto (default)    — tries backslash-escape first, falls back to RFC 4180
#   :double_quotes     — RFC 4180: backslash is literal
#   :backslash         — MySQL/Unix: \" is an escaped quote

[true, false].each do |bool|
  describe "backslash in quoted fields with#{bool ? ' C-' : 'out '}acceleration" do

    # =========================================================================
    # quote_escaping: :double_quotes (default) — RFC 4180 behavior
    # Backslash has NO special meaning; it's a literal character.
    # =========================================================================
    context 'with quote_escaping: :double_quotes' do
      let(:options) { { acceleration: bool, quote_escaping: :double_quotes } }

      context 'quoted field ending with a backslash' do
        let(:csv) { "Col A,Col B\n\"X,Y\\\",Y" }

        it 'treats backslash as literal and closes the field at the quote' do
          result = SmarterCSV.process(StringIO.new(csv), **options)
          expect(result.size).to eq 1
          expect(result[0][:"col_a"]).to eq "X,Y\\"
          expect(result[0][:"col_b"]).to eq "Y"
        end
      end

      context 'quoted field with backslash followed by other characters' do
        let(:csv) { "Col A,Col B\n\"X,Y\\ok\",Y" }

        it 'preserves the backslash in the field value' do
          result = SmarterCSV.process(StringIO.new(csv), **options)
          expect(result.size).to eq 1
          expect(result[0][:"col_a"]).to eq "X,Y\\ok"
          expect(result[0][:"col_b"]).to eq "Y"
        end
      end

      context 'quoted field containing only a backslash' do
        let(:csv) { "Col A,Col B\n\"\\\",Y" }

        it 'parses the backslash as the field value' do
          result = SmarterCSV.process(StringIO.new(csv), **options)
          expect(result.size).to eq 1
          expect(result[0][:"col_a"]).to eq "\\"
          expect(result[0][:"col_b"]).to eq "Y"
        end
      end

      context 'quoted field ending with double backslash' do
        let(:csv) { "Col A,Col B\n\"X,Y\\\\\",Z" }

        it 'preserves both backslashes' do
          result = SmarterCSV.process(StringIO.new(csv), **options)
          expect(result.size).to eq 1
          expect(result[0][:"col_a"]).to eq "X,Y\\\\"
          expect(result[0][:"col_b"]).to eq "Z"
        end
      end

      context 'multiple rows with backslash at end of quoted field' do
        let(:csv) { "Col A,Col B\n\"path\\to\\\",val1\n\"another\\\",val2" }

        it 'parses all rows with backslash as literal' do
          result = SmarterCSV.process(StringIO.new(csv), **options)
          expect(result.size).to eq 2
          expect(result[0][:"col_a"]).to eq "path\\to\\"
          expect(result[0][:"col_b"]).to eq "val1"
          expect(result[1][:"col_a"]).to eq "another\\"
          expect(result[1][:"col_b"]).to eq "val2"
        end
      end

      context 'Windows file path in quoted field' do
        let(:csv) { "path,label\n\"C:\\Users\\Docs\\\",important" }

        it 'preserves the full Windows path' do
          result = SmarterCSV.process(StringIO.new(csv), **options)
          expect(result.size).to eq 1
          expect(result[0][:path]).to eq "C:\\Users\\Docs\\"
          expect(result[0][:label]).to eq "important"
        end
      end
    end

    # =========================================================================
    # quote_escaping: :auto — tries backslash first, falls back to RFC 4180
    # =========================================================================
    context 'with quote_escaping: :auto' do
      let(:options) { { acceleration: bool, quote_escaping: :auto } }

      context 'Issue #316: quoted field ending with backslash (fallback to RFC)' do
        let(:csv) { "Col A,Col B\n\"X,Y\\\",Y" }

        it 'falls back to RFC 4180 and treats backslash as literal' do
          result = SmarterCSV.process(StringIO.new(csv), **options)
          expect(result.size).to eq 1
          expect(result[0][:"col_a"]).to eq "X,Y\\"
          expect(result[0][:"col_b"]).to eq "Y"
        end
      end

      context 'quoted field containing only a backslash (fallback to RFC)' do
        let(:csv) { "Col A,Col B\n\"\\\",Y" }

        it 'falls back to RFC and parses backslash as the field value' do
          result = SmarterCSV.process(StringIO.new(csv), **options)
          expect(result.size).to eq 1
          expect(result[0][:"col_a"]).to eq "\\"
          expect(result[0][:"col_b"]).to eq "Y"
        end
      end

      context 'RFC doubled quotes still work under :auto' do
        let(:csv) { "col_a,col_b\n\"She said \"\"hello\"\"\",note" }

        it 'handles RFC doubled quotes correctly' do
          result = SmarterCSV.process(StringIO.new(csv), **options)
          expect(result.size).to eq 1
          expect(result[0][:col_a]).to eq 'She said "hello"'
          expect(result[0][:col_b]).to eq "note"
        end
      end

      context 'backslash in middle of field (not before a quote)' do
        let(:csv) { "Col A,Col B\n\"X,Y\\ok\",Y" }

        it 'preserves the backslash as literal' do
          result = SmarterCSV.process(StringIO.new(csv), **options)
          expect(result.size).to eq 1
          expect(result[0][:"col_a"]).to eq "X,Y\\ok"
          expect(result[0][:"col_b"]).to eq "Y"
        end
      end

      context 'Windows file path in quoted field (fallback to RFC)' do
        let(:csv) { "path,label\n\"C:\\Users\\Docs\\\",important" }

        it 'preserves the full Windows path' do
          result = SmarterCSV.process(StringIO.new(csv), **options)
          expect(result.size).to eq 1
          expect(result[0][:path]).to eq "C:\\Users\\Docs\\"
          expect(result[0][:label]).to eq "important"
        end
      end

      context 'multiple rows with mixed quoting styles' do
        let(:csv) { "col_a,col_b\n\"path\\to\\\",val1\n\"normal\",val2" }

        it 'handles each row independently without state leakage' do
          result = SmarterCSV.process(StringIO.new(csv), **options)
          expect(result.size).to eq 2
          expect(result[0][:col_a]).to eq "path\\to\\"
          expect(result[0][:col_b]).to eq "val1"
          expect(result[1][:col_a]).to eq "normal"
          expect(result[1][:col_b]).to eq "val2"
        end
      end

      context 'multiline quoted field still works under :auto' do
        let(:csv) { "col_a,col_b\n\"line1\nline2\",val" }

        it 'correctly stitches multiline fields' do
          result = SmarterCSV.process(StringIO.new(csv), **options)
          expect(result.size).to eq 1
          expect(result[0][:col_a]).to eq "line1\nline2"
          expect(result[0][:col_b]).to eq "val"
        end
      end

      context 'field ending with double backslash' do
        let(:csv) { "Col A,Col B\n\"X,Y\\\\\",Z" }

        it 'preserves both backslashes (both modes agree)' do
          result = SmarterCSV.process(StringIO.new(csv), **options)
          expect(result.size).to eq 1
          expect(result[0][:"col_a"]).to eq "X,Y\\\\"
          expect(result[0][:"col_b"]).to eq "Z"
        end
      end
    end

    # =========================================================================
    # quote_escaping: :backslash — MySQL/Unix convention
    # Backslash before a quote char IS an escape: \" means literal "
    # =========================================================================
    context 'with quote_escaping: :backslash' do
      let(:options) { { acceleration: bool, quote_escaping: :backslash } }

      context 'backslash-escaped quote inside a quoted field' do
        let(:csv) { "Col A,Col B\n\"X,Y\\\"ok\",Z" }

        it 'treats backslash-quote as an escaped quote, keeping the field open' do
          result = SmarterCSV.process(StringIO.new(csv), **options)
          expect(result.size).to eq 1
          expect(result[0][:"col_a"]).to eq "X,Y\\\"ok"
          expect(result[0][:"col_b"]).to eq "Z"
        end
      end

      context 'field with multiple backslash-escaped quotes' do
        # CSV: "She said \"hello\" and \"goodbye\"",note
        let(:csv) { "col_a,col_b\n\"She said \\\"hello\\\" and \\\"goodbye\\\"\",note" }

        it 'keeps all escaped quotes in the field value' do
          result = SmarterCSV.process(StringIO.new(csv), **options)
          expect(result.size).to eq 1
          expect(result[0][:col_a]).to eq "She said \\\"hello\\\" and \\\"goodbye\\\""
          expect(result[0][:col_b]).to eq "note"
        end
      end

      context 'field ending with double backslash (even count)' do
        # "abc\\",def — even backslashes, so the quote closes normally
        let(:csv) { "col_a,col_b\n\"abc\\\\\",def" }

        it 'treats double backslash as literal and closes the field' do
          result = SmarterCSV.process(StringIO.new(csv), **options)
          expect(result.size).to eq 1
          expect(result[0][:col_a]).to eq "abc\\\\"
          expect(result[0][:col_b]).to eq "def"
        end
      end

      context 'field ending with single backslash (odd count — escapes the closing quote)' do
        # "abc\",def — odd backslash escapes the quote, field is unclosed
        let(:csv) { "col_a,col_b\n\"abc\\\",def" }

        it 'raises MalformedCSV because the closing quote is escaped' do
          expect {
            SmarterCSV.process(StringIO.new(csv), **options)
          }.to raise_error(SmarterCSV::MalformedCSV)
        end
      end

      context 'backslash in middle of field (not before a quote)' do
        let(:csv) { "Col A,Col B\n\"X,Y\\ok\",Y" }

        it 'preserves the backslash as literal' do
          result = SmarterCSV.process(StringIO.new(csv), **options)
          expect(result.size).to eq 1
          expect(result[0][:"col_a"]).to eq "X,Y\\ok"
          expect(result[0][:"col_b"]).to eq "Y"
        end
      end
    end
  end
end

# =========================================================================
# Priority 3: multi-char col_sep + quote_escaping: :auto
#
# :auto logic has three code paths (both C and Ruby):
#   1. No backslash in line  → Opt #5: RFC mode called directly (no try-backslash dance)
#   2. Backslash present, backslash mode succeeds → backslash result used
#   3. Backslash before closing quote → backslash returns -1 (unclosed), RFC fallback
#
# Multi-char col_sep forces the slow (character-by-character) path in both C
# and Ruby, exercising Section 5 of the C extension and the multi-char branch
# of parse_csv_line_ruby. Tests run with both acceleration settings to verify
# C/Ruby parity.
# =========================================================================
[true, false].each do |acceleration|
  describe "quote_escaping: :auto + multi-char col_sep with#{acceleration ? ' C-' : 'out '}acceleration" do
    let(:base_options) { { acceleration: acceleration, col_sep: '::' } }

    # --- Path 1: no backslash → Opt #5 fires, RFC mode used directly ---

    context 'no backslash in line (Opt #5)' do
      it 'handles a quoted field containing the multi-char separator' do
        # No backslash → Opt #5 fires; RFC mode is used; col_sep inside the quoted
        # field must be treated as content, not a separator.
        csv = StringIO.new("col_a::col_b\n\"hel::lo\"::Z\n")
        data = SmarterCSV.process(csv, **base_options)
        expect(data.size).to eq 1
        expect(data[0][:col_a]).to eq 'hel::lo'
        expect(data[0][:col_b]).to eq 'Z'
      end

      it 'parses plain unquoted fields without backslash' do
        csv = StringIO.new("name::value\nAlice::42\n")
        data = SmarterCSV.process(csv, **base_options)
        expect(data.size).to eq 1
        expect(data[0][:name]).to eq 'Alice'
        expect(data[0][:value]).to eq 42
      end
    end

    # --- Path 2: backslash mid-field (not before a quote) → backslash mode succeeds ---

    context 'backslash mid-field, not before a closing quote (path 2)' do
      it 'parses correctly and backslash is preserved as literal' do
        # "X\ok"::Z — backslash not immediately before the closing quote,
        # so backslash mode closes the field normally at the "
        csv = StringIO.new("col_a::col_b\n\"X\\ok\"::Z\n")
        data = SmarterCSV.process(csv, **base_options)
        expect(data.size).to eq 1
        expect(data[0][:col_a]).to eq 'X\\ok'
        expect(data[0][:col_b]).to eq 'Z'
      end

      it 'handles col_sep inside quoted field alongside a mid-field backslash' do
        # "A\::B"::C — col_sep :: is inside the quoted field (not a separator);
        # backslash is mid-field, not before a quote → field closes at the "
        csv = StringIO.new("col_a::col_b\n\"A\\::B\"::C\n")
        data = SmarterCSV.process(csv, **base_options)
        expect(data.size).to eq 1
        expect(data[0][:col_a]).to eq 'A\\::B'
        expect(data[0][:col_b]).to eq 'C'
      end
    end

    # --- Path 3: backslash before closing quote → RFC 4180 fallback ---

    context 'backslash before closing quote (issue #316 analogue — path 3)' do
      it 'falls back to RFC 4180 and treats backslash as literal' do
        # "path\"::Z
        # Backslash mode: \" is an escaped quote, field stays open; ::Z consumed as
        # content; EOL → unclosed → returns -1.
        # RFC mode:       \ is literal, " closes the field (followed by ::); col_b = Z.
        csv = StringIO.new("col_a::col_b\n\"path\\\"::Z\n")
        data = SmarterCSV.process(csv, **base_options)
        expect(data.size).to eq 1
        expect(data[0][:col_a]).to eq 'path\\'
        expect(data[0][:col_b]).to eq 'Z'
      end
    end

    # --- C / Ruby parity across all three paths ---

    it 'C and Ruby produce identical results across all three :auto paths' do
      scenarios = [
        "col_a::col_b\n\"hel::lo\"::Z\n",    # path 1: no backslash, Opt #5
        "col_a::col_b\nplain::value\n",       # path 1: no quotes, no backslash
        "col_a::col_b\n\"X\\ok\"::Z\n",       # path 2: backslash mid-field
        "col_a::col_b\n\"A\\::B\"::C\n",      # path 2: backslash mid-field + sep inside
        "col_a::col_b\n\"path\\\"::Z\n",      # path 3: backslash→RFC fallback
      ]
      scenarios.each do |csv_content|
        c_data    = SmarterCSV.process(StringIO.new(csv_content), col_sep: '::', acceleration: true)
        ruby_data = SmarterCSV.process(StringIO.new(csv_content), col_sep: '::', acceleration: false)
        expect(c_data).to eq(ruby_data), "Mismatch for CSV: #{csv_content.inspect}"
      end
    end
  end
end

# =========================================================================
# quote_escaping: :backslash + numeric conversion
#
# After the fix to insert_field_into_hash (quoted fields now go through the
# full transformation pipeline), verify that backslash-quoted numeric fields
# are correctly converted — i.e. the two fixes interact correctly.
# =========================================================================
[true, false].each do |acceleration|
  describe "quote_escaping: :backslash + numeric conversion with#{acceleration ? ' C-' : 'out '}acceleration" do
    let(:base_options) { { acceleration: acceleration, quote_escaping: :backslash } }

    it 'converts quoted integers and floats to numeric' do
      csv = StringIO.new("name,age,score\nAlice,\"42\",\"3.14\"\n")
      data = SmarterCSV.process(csv, **base_options)
      expect(data[0][:age]).to eq 42
      expect(data[0][:age]).to be_a(Integer)
      expect(data[0][:score]).to eq 3.14
      expect(data[0][:score]).to be_a(Float)
    end

    it 'removes quoted zero values when remove_zero_values is true' do
      csv = StringIO.new("name,count,score\nAlice,\"0\",\"3.14\"\n")
      data = SmarterCSV.process(csv, **base_options.merge(remove_zero_values: true, remove_empty_values: true))
      expect(data[0]).not_to have_key(:count)
      expect(data[0][:score]).to eq 3.14
    end

    it 'leaves quoted numerics as strings when convert_values_to_numeric: false' do
      csv = StringIO.new("name,age\nAlice,\"42\"\n")
      data = SmarterCSV.process(csv, **base_options.merge(convert_values_to_numeric: false))
      expect(data[0][:age]).to eq '42'
      expect(data[0][:age]).to be_a(String)
    end

    it 'C and Ruby produce identical results' do
      csv_content = "name,age,score,zero\nAlice,\"42\",\"3.14\",\"0\"\n"
      c_data    = SmarterCSV.process(StringIO.new(csv_content), quote_escaping: :backslash, acceleration: true)
      ruby_data = SmarterCSV.process(StringIO.new(csv_content), quote_escaping: :backslash, acceleration: false)
      expect(c_data).to eq ruby_data
    end
  end
end
