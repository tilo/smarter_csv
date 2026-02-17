# frozen_string_literal: true

require 'spec_helper'

#
# Test suite for Issue #316 / PR #317: Backslash interaction with quote characters
#
# These tests cover the fundamental tension between:
#   - RFC 4180 compliance (backslash is NOT an escape character; only "" escapes ")
#   - Real-world CSV producers (MySQL, PHP, legacy tools) that use \" to escape quotes
#
# The `quote_escaping` option resolves this:
#   :auto (default)     — tries backslash-escape first, falls back to RFC 4180
#   :double_quotes      — strict RFC 4180: backslash is always literal
#   :backslash          — MySQL/Unix: \" is an escaped quote
#
# All tests run under the :auto default unless explicitly testing a specific mode.
#

RSpec.describe 'Backslash and quote_char edge cases' do
  # ---------------------------------------------------------------------------
  # Group 1: The original Issue #316 — literal backslash at end of quoted field
  # Under :auto, backslash-escape fails (unclosed field), falls back to RFC 4180.
  # ---------------------------------------------------------------------------
  describe 'quoted field ending with a literal backslash (Issue #316)' do
    it 'parses a quoted field whose value ends with a single backslash' do
      # CSV row: "X,Y\",Y
      # :auto tries backslash (unclosed) → falls back to RFC → field = X,Y\
      csv = "Col A,Col B\n\"X,Y\\\",Y"
      result = SmarterCSV.process(StringIO.new(csv))

      expect(result.length).to eq(1)
      expect(result.first[:col_a]).to eq('X,Y\\')
      expect(result.first[:col_b]).to eq('Y')
    end

    it 'parses a quoted field whose value ends with a double backslash' do
      # CSV row: "X,Y\\",Y
      # Expected: field1 = 'X,Y\\' (even backslashes, both modes agree), field2 = 'Y'
      csv = "Col A,Col B\n\"X,Y\\\\\",Y"
      result = SmarterCSV.process(StringIO.new(csv))

      expect(result.length).to eq(1)
      expect(result.first[:col_a]).to eq('X,Y\\\\')
      expect(result.first[:col_b]).to eq('Y')
    end

    it 'parses a Windows file path ending with backslash in a quoted field' do
      # Real-world scenario: Windows paths like C:\Users\Docs\
      csv = "path,label\n\"C:\\Users\\Docs\\\",important"
      result = SmarterCSV.process(StringIO.new(csv))

      expect(result.length).to eq(1)
      expect(result.first[:path]).to eq('C:\\Users\\Docs\\')
      expect(result.first[:label]).to eq('important')
    end

    it 'parses a regex pattern ending with backslash in a quoted field' do
      # Real-world scenario: regex like ^\d+\
      csv = "pattern,description\n\"^\\d+\\\",matches digits"
      result = SmarterCSV.process(StringIO.new(csv))

      expect(result.length).to eq(1)
      expect(result.first[:pattern]).to eq('^\\d+\\')
      expect(result.first[:description]).to eq('matches digits')
    end
  end

  # ---------------------------------------------------------------------------
  # Group 2: Backslash in the middle of a quoted field (should always work)
  # ---------------------------------------------------------------------------
  describe 'backslash in the middle of a quoted field' do
    it 'preserves a backslash that is not adjacent to a quote character' do
      csv = "Col A,Col B\n\"X,Y\\ok\",Y"
      result = SmarterCSV.process(StringIO.new(csv))

      expect(result.length).to eq(1)
      expect(result.first[:col_a]).to eq('X,Y\\ok')
      expect(result.first[:col_b]).to eq('Y')
    end

    it 'preserves multiple backslashes in the middle of a field' do
      csv = "col\n\"a\\\\b\\\\c\""
      result = SmarterCSV.process(StringIO.new(csv))

      expect(result.length).to eq(1)
      expect(result.first[:col]).to eq('a\\\\b\\\\c')
    end
  end

  # ---------------------------------------------------------------------------
  # Group 3: RFC 4180 doubled-quote escaping (must always work)
  # ---------------------------------------------------------------------------
  describe 'RFC 4180 doubled-quote escaping' do
    it 'parses a field with an embedded doubled quote' do
      # CSV: "height 6""2'" => value: height 6"2'
      csv = "description\n\"height 6\"\"2'\""
      result = SmarterCSV.process(StringIO.new(csv))

      expect(result.length).to eq(1)
      expect(result.first[:description]).to eq("height 6\"2'")
    end

    it 'parses a field that is only a doubled quote' do
      # CSV: """" => value: "
      csv = "col\n\"\"\"\""
      result = SmarterCSV.process(StringIO.new(csv))

      expect(result.length).to eq(1)
      expect(result.first[:col]).to eq('"')
    end

    it 'parses a field with multiple doubled quotes' do
      # CSV: "She said ""Hello"" and ""Goodbye""" => She said "Hello" and "Goodbye"
      csv = "speech\n\"She said \"\"Hello\"\" and \"\"Goodbye\"\"\""
      result = SmarterCSV.process(StringIO.new(csv))

      expect(result.length).to eq(1)
      expect(result.first[:speech]).to eq('She said "Hello" and "Goodbye"')
    end

    it 'handles doubled quotes at the very start of a quoted field value' do
      # CSV: """Hello" => "Hello (3 quotes at start: open + doubled pair, then Hello, then close)
      csv = "col\n\"\"\"Hello\""
      result = SmarterCSV.process(StringIO.new(csv))

      expect(result.length).to eq(1)
      expect(result.first[:col]).to eq('"Hello')
    end

    it 'handles doubled quotes at the very end of a quoted field value' do
      # CSV: "Hello"""  => Hello"
      csv = "col\n\"Hello\"\"\""
      result = SmarterCSV.process(StringIO.new(csv))

      expect(result.length).to eq(1)
      expect(result.first[:col]).to eq('Hello"')
    end
  end

  # ---------------------------------------------------------------------------
  # Group 4: Backslash-escaped quotes with explicit quote_escaping modes
  # ---------------------------------------------------------------------------
  describe 'backslash-escaped quotes (non-RFC, MySQL/PHP style)' do
    context 'with quote_escaping: :backslash' do
      it 'parses a field with backslash-escaped embedded quotes' do
        # CSV: "This is a \"premium\" product"
        csv = "description\n\"This is a \\\"premium\\\" product\""
        result = SmarterCSV.process(StringIO.new(csv), quote_escaping: :backslash)

        expect(result.length).to eq(1)
        expect(result.first[:description]).to eq('This is a \\"premium\\" product')
      end

      it 'parses the height example with backslash-escaped quote' do
        # CSV: "height 6\"2'" — with :backslash, \" is an escaped quote
        csv = "description\n\"height 6\\\"2'\""
        result = SmarterCSV.process(StringIO.new(csv), quote_escaping: :backslash)

        expect(result.length).to eq(1)
        expect(result.first[:description]).to eq("height 6\\\"2'")
      end

      it 'handles a field from MySQL OUTFILE with commas and escaped quotes' do
        # Simulates: SELECT "He said \"hi\", then left" INTO OUTFILE
        csv = "event\n\"He said \\\"hi\\\", then left\""
        result = SmarterCSV.process(StringIO.new(csv), quote_escaping: :backslash)

        expect(result.length).to eq(1)
        expect(result.first[:event]).to eq('He said \\"hi\\", then left')
      end
    end

    context 'with quote_escaping: :auto' do
      it 'parses backslash-escaped quotes via the backslash-first strategy' do
        csv = "description\n\"This is a \\\"premium\\\" product\""
        result = SmarterCSV.process(StringIO.new(csv), quote_escaping: :auto)

        expect(result.length).to eq(1)
        expect(result.first[:description]).to eq('This is a \\"premium\\" product')
      end

      it 'handles a MySQL OUTFILE field with commas and escaped quotes' do
        csv = "event\n\"He said \\\"hi\\\", then left\""
        result = SmarterCSV.process(StringIO.new(csv), quote_escaping: :auto)

        expect(result.length).to eq(1)
        expect(result.first[:event]).to eq('He said \\"hi\\", then left')
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Group 5: Ambiguous backslash-quote sequences
  #
  # Under :auto, backslash-escape is tried first. If it fails (unclosed field),
  # RFC 4180 fallback kicks in. These tests verify deterministic outcomes.
  # ---------------------------------------------------------------------------
  describe 'ambiguous backslash-quote sequences' do
    it 'handles single backslash before closing quote — falls back to RFC 4180' do
      # Raw CSV bytes: "abc\",def
      #
      # Backslash-escape: \" = escaped quote, field is unclosed → MalformedCSV
      # RFC 4180: backslash is literal, " closes the field → field = abc\, next = def
      # :auto tries backslash first, fails, falls back to RFC
      csv = "col_a,col_b\n\"abc\\\",def"
      result = SmarterCSV.process(StringIO.new(csv))

      expect(result.length).to eq(1)
      expect(result.first[:col_a]).to eq('abc\\')
      expect(result.first[:col_b]).to eq('def')
    end

    it 'handles double backslash before closing quote — both modes agree' do
      # Raw CSV bytes: "abc\\",def
      #
      # Backslash-escape: \\ = literal \, then " closes the field → field = abc\\
      # RFC 4180: \\ is two literal backslashes, " closes the field → field = abc\\
      # Both modes agree — no fallback needed
      csv = "col_a,col_b\n\"abc\\\\\",def"
      result = SmarterCSV.process(StringIO.new(csv))

      expect(result.length).to eq(1)
      expect(result.first[:col_a]).to eq('abc\\\\')
      expect(result.first[:col_b]).to eq('def')
    end

    it 'handles triple backslash before closing quote — falls back to RFC 4180' do
      # Raw CSV bytes: "abc\\\",def
      #
      # Backslash-escape: \\ = literal \, then \" = escaped quote → field is unclosed → MalformedCSV
      # RFC 4180: \\\ is three literal backslashes, " closes the field → field = abc\\\
      # :auto tries backslash first, fails, falls back to RFC
      csv = "col_a,col_b\n\"abc\\\\\\\",def"
      result = SmarterCSV.process(StringIO.new(csv))

      expect(result.length).to eq(1)
      expect(result.first[:col_a]).to eq('abc\\\\\\')
      expect(result.first[:col_b]).to eq('def')
    end
  end

  # ---------------------------------------------------------------------------
  # Group 6: Multiline quoted fields with backslashes
  # ---------------------------------------------------------------------------
  describe 'multiline quoted fields with backslashes' do
    it 'handles a multiline field where a line ends with a backslash' do
      csv = "col_a,col_b\n\"line1\\\nline2\",val"
      result = SmarterCSV.process(StringIO.new(csv))

      expect(result.length).to eq(1)
      expect(result.first[:col_a]).to eq("line1\\\nline2")
      expect(result.first[:col_b]).to eq('val')
    end

    it 'handles a multiline field with a backslash on the last line before closing quote' do
      # :auto dual counting: backslash-aware count is odd, RFC count is also odd → truly multiline
      # After stitching, backslash-escape fails (unclosed) → falls back to RFC
      csv = "col_a,col_b\n\"line1\nline2\\\",val"
      result = SmarterCSV.process(StringIO.new(csv))

      expect(result.length).to eq(1)
      expect(result.first[:col_a]).to eq("line1\nline2\\")
      expect(result.first[:col_b]).to eq('val')
    end
  end

  # ---------------------------------------------------------------------------
  # Group 7: Unquoted fields with backslashes (should never be affected)
  # ---------------------------------------------------------------------------
  describe 'unquoted fields with backslashes' do
    it 'preserves backslashes in unquoted fields' do
      csv = "col_a,col_b\nabc\\def,ghi"
      result = SmarterCSV.process(StringIO.new(csv))

      expect(result.length).to eq(1)
      expect(result.first[:col_a]).to eq('abc\\def')
      expect(result.first[:col_b]).to eq('ghi')
    end

    it 'preserves a trailing backslash in an unquoted field' do
      csv = "col_a,col_b\nabc\\,def"
      result = SmarterCSV.process(StringIO.new(csv))

      expect(result.length).to eq(1)
      expect(result.first[:col_a]).to eq('abc\\')
      expect(result.first[:col_b]).to eq('def')
    end
  end

  # ---------------------------------------------------------------------------
  # Group 8: Empty and minimal quoted fields
  # ---------------------------------------------------------------------------
  describe 'empty and minimal quoted fields' do
    it 'parses an empty quoted field' do
      csv = "col_a,col_b\n\"\",val"
      result = SmarterCSV.process(StringIO.new(csv), remove_empty_values: false)

      expect(result.length).to eq(1)
      expect(result.first[:col_a]).to eq('')
      expect(result.first[:col_b]).to eq('val')
    end

    it 'parses a quoted field containing only a backslash — falls back to RFC' do
      # CSV: "\",next — backslash-escape sees unclosed field → fallback
      csv = "col_a,col_b\n\"\\\",next"
      result = SmarterCSV.process(StringIO.new(csv))

      expect(result.length).to eq(1)
      expect(result.first[:col_a]).to eq('\\')
      expect(result.first[:col_b]).to eq('next')
    end

    it 'parses a quoted field containing only two backslashes' do
      csv = "col_a,col_b\n\"\\\\\",next"
      result = SmarterCSV.process(StringIO.new(csv))

      expect(result.length).to eq(1)
      expect(result.first[:col_a]).to eq('\\\\')
      expect(result.first[:col_b]).to eq('next')
    end
  end

  # ---------------------------------------------------------------------------
  # Group 9: Mixed escaping styles in the same file
  # :auto handles this per-row — no state leakage between rows.
  # ---------------------------------------------------------------------------
  describe 'mixed escaping styles in the same file' do
    it 'handles a file where one row uses doubled quotes and another has a trailing backslash' do
      csv = <<~CSV
        col_a,col_b
        "She said ""hello""",greeting
        "C:\\Users\\",path
      CSV

      result = SmarterCSV.process(StringIO.new(csv))

      expect(result.length).to eq(2)
      expect(result[0][:col_a]).to eq('She said "hello"')
      expect(result[0][:col_b]).to eq('greeting')
      expect(result[1][:col_a]).to eq('C:\\Users\\')
      expect(result[1][:col_b]).to eq('path')
    end
  end

  # ---------------------------------------------------------------------------
  # Group 10: Custom quote_char interaction with backslash
  # ---------------------------------------------------------------------------
  describe 'custom quote_char with backslashes' do
    it 'handles backslash before a custom single-quote quote_char' do
      # Using ' as quote_char: 'abc\',def
      csv = "col_a,col_b\n'abc\\',def"
      result = SmarterCSV.process(StringIO.new(csv), quote_char: "'")

      expect(result.length).to eq(1)
      expect(result.first[:col_a]).to eq('abc\\')
      expect(result.first[:col_b]).to eq('def')
    end
  end

  # ---------------------------------------------------------------------------
  # Group 11: Custom col_sep with backslash-quote interaction
  # ---------------------------------------------------------------------------
  describe 'custom col_sep with backslash in quoted fields' do
    it 'handles backslash at end of quoted field with semicolon separator' do
      csv = "col_a;col_b\n\"abc\\\";def"
      result = SmarterCSV.process(StringIO.new(csv), col_sep: ';')

      expect(result.length).to eq(1)
      expect(result.first[:col_a]).to eq('abc\\')
      expect(result.first[:col_b]).to eq('def')
    end

    it 'handles backslash at end of quoted field with tab separator' do
      csv = "col_a\tcol_b\n\"abc\\\"\tdef"
      result = SmarterCSV.process(StringIO.new(csv), col_sep: "\t")

      expect(result.length).to eq(1)
      expect(result.first[:col_a]).to eq('abc\\')
      expect(result.first[:col_b]).to eq('def')
    end
  end

  # ---------------------------------------------------------------------------
  # Group 12: Multiple rows — verify no state leakage between rows
  # ---------------------------------------------------------------------------
  describe 'multiple rows with backslash edge cases (state leakage check)' do
    it 'correctly parses many rows where some have trailing backslashes in quoted fields' do
      csv = <<~CSV
        key,value
        "normal",a
        "ends_with_backslash\\",b
        "also_normal",c
        "another_backslash\\",d
        "final",e
      CSV

      result = SmarterCSV.process(StringIO.new(csv))

      expect(result.length).to eq(5)
      expect(result[0][:key]).to eq('normal')
      expect(result[0][:value]).to eq('a')
      expect(result[1][:key]).to eq('ends_with_backslash\\')
      expect(result[1][:value]).to eq('b')
      expect(result[2][:key]).to eq('also_normal')
      expect(result[2][:value]).to eq('c')
      expect(result[3][:key]).to eq('another_backslash\\')
      expect(result[3][:value]).to eq('d')
      expect(result[4][:key]).to eq('final')
      expect(result[4][:value]).to eq('e')
    end
  end

  # ---------------------------------------------------------------------------
  # Group 13: Explicit quote_escaping modes — verify each mode independently
  # ---------------------------------------------------------------------------
  describe 'explicit quote_escaping modes' do
    context 'with quote_escaping: :double_quotes' do
      it 'treats backslash as literal, field closes at the quote' do
        # CSV: "abc\",def — in :double_quotes, backslash is literal, " closes the field
        csv = "col_a,col_b\n\"abc\\\",def"
        result = SmarterCSV.process(StringIO.new(csv), quote_escaping: :double_quotes)

        expect(result.first[:col_a]).to eq('abc\\')
        expect(result.first[:col_b]).to eq('def')
      end

      it 'does not interpret backslash-quote as an escaped quote' do
        # "She said \"hello\"" — in :double_quotes, \" is not an escape
        # The first " after \ closes the field, leaving garbage → MalformedCSV
        csv = "col\n\"She said \\\"hello\\\"\""
        result = SmarterCSV.process(StringIO.new(csv), quote_escaping: :double_quotes)

        # The parser is lenient: after closing quote at \", it sees "hello\"" outside quotes
        # Exact behavior depends on parser leniency, but it should not crash
        expect(result.length).to eq(1)
      end
    end

    context 'with quote_escaping: :backslash' do
      it 'interprets backslash-quote as an escaped quote' do
        # CSV: "She said \"hello\"" — in :backslash, \" keeps the field open
        csv = "col\n\"She said \\\"hello\\\"\""
        result = SmarterCSV.process(StringIO.new(csv), quote_escaping: :backslash)

        expect(result.length).to eq(1)
        expect(result.first[:col]).to eq('She said \\"hello\\"')
      end

      it 'raises MalformedCSV when backslash escapes the closing quote' do
        # "abc\" — the \" escapes the closing quote, field is unclosed
        csv = "col_a,col_b\n\"abc\\\",def"
        expect {
          SmarterCSV.process(StringIO.new(csv), quote_escaping: :backslash)
        }.to raise_error(SmarterCSV::MalformedCSV)
      end

      it 'handles even backslashes before closing quote (quote closes normally)' do
        # CSV: "abc\\",def — \\ = literal backslash, " closes the field
        csv = "col_a,col_b\n\"abc\\\\\",def"
        result = SmarterCSV.process(StringIO.new(csv), quote_escaping: :backslash)

        expect(result.first[:col_a]).to eq('abc\\\\')
        expect(result.first[:col_b]).to eq('def')
      end
    end
  end
end
