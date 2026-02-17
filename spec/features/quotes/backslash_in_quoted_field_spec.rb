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
