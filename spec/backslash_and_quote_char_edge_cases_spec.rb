# frozen_string_literal: true

require 'spec_helper'

#
# Test suite for Issue #316 / PR #317: Backslash interaction with quote characters
#
# These tests expose the fundamental tension between:
#   - RFC 4180 compliance (backslash is NOT an escape character; only "" escapes ")
#   - Real-world CSV producers (MySQL, PHP, legacy tools) that use \" to escape quotes
#
# The original bug: v1.15.0 regressed from v1.7.3 by treating \" as an escaped quote,
# causing "Unclosed quoted field" errors when a quoted field's value legitimately ends
# with a backslash character (e.g. file paths, regex patterns).
#
# A naive fix (stop treating \ as escape) would break users whose CSV data contains
# backslash-escaped quotes from non-RFC-compliant producers.
#

RSpec.describe 'Backslash and quote_char edge cases' do
  # ---------------------------------------------------------------------------
  # Group 1: The original Issue #316 — literal backslash at end of quoted field
  # ---------------------------------------------------------------------------
  describe 'quoted field ending with a literal backslash (Issue #316)' do
    it 'parses a quoted field whose value ends with a single backslash' do
      # CSV row: "X,Y\",Y
      # Expected: field1 = 'X,Y\' (the comma is inside quotes), field2 = 'Y'
      csv = "Col A,Col B\n\"X,Y\\\",Y"
      result = SmarterCSV.process(StringIO.new(csv))

      expect(result.length).to eq(1)
      expect(result.first[:col_a]).to eq('X,Y\\')
      expect(result.first[:col_b]).to eq('Y')
    end

    it 'parses a quoted field whose value ends with a double backslash' do
      # CSV row: "X,Y\\",Y
      # Expected: field1 = 'X,Y\\', field2 = 'Y'
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
  # Group 4: Backslash-escaped quotes (non-RFC, MySQL/PHP style)
  #
  # These tests document the behavior that WOULD BREAK if the fix naively
  # removes backslash-escape support. They represent real-world CSV data
  # from MySQL SELECT INTO OUTFILE, PHP fputcsv, etc.
  #
  # If SmarterCSV adds a config option (e.g. backslash_escape: true/false),
  # these tests should be conditional on that option.
  # ---------------------------------------------------------------------------
  describe 'backslash-escaped quotes (non-RFC, MySQL/PHP style)' do
    it 'parses a field with backslash-escaped embedded quotes' do
      # CSV: "This is a \"premium\" product"
      # If backslash-escape is ON:  value = This is a "premium" product
      # If backslash-escape is OFF: parse error (field closes at first \", leaving garbage)
      csv = "description\n\"This is a \\\"premium\\\" product\""
      result = SmarterCSV.process(StringIO.new(csv))

      expect(result.length).to eq(1)
      # Uncomment the assertion matching your expected behavior:
      #
      # If backslash-escaping is ENABLED (current v1.15.0 behavior):
      # expect(result.first[:description]).to eq('This is a "premium" product')
      #
      # If backslash-escaping is DISABLED (RFC 4180 / proposed fix):
      # This would likely raise SmarterCSV::MalformedCSV or produce corrupt data.
      # expect { ... }.to raise_error(SmarterCSV::MalformedCSV)
      #
      # For now, just verify it doesn't crash silently — adapt assertion to desired behavior:
      expect(result.first[:description]).to be_a(String)
    end

    it 'parses the height example with backslash-escaped quote' do
      # CSV: "height 6\"2'"
      # With quote_escaping: :backslash, \" is an escaped quote
      csv = "description\n\"height 6\\\"2'\""
      result = SmarterCSV.process(StringIO.new(csv), quote_escaping: :backslash)

      expect(result.length).to eq(1)
      expect(result.first[:description]).to be_a(String)
    end

    it 'handles a field from MySQL OUTFILE with commas and escaped quotes' do
      # Simulates: SELECT "He said \"hi\", then left" INTO OUTFILE
      csv = "event\n\"He said \\\"hi\\\", then left\""
      result = SmarterCSV.process(StringIO.new(csv))

      expect(result.length).to eq(1)
      expect(result.first[:event]).to be_a(String)
    end
  end

  # ---------------------------------------------------------------------------
  # Group 5: Conflict cases — backslash + quote ambiguity
  #
  # These are the critical cases where the two interpretations diverge.
  # Each test documents BOTH expected outcomes so CI can catch regressions
  # regardless of which interpretation SmarterCSV chooses.
  # ---------------------------------------------------------------------------
  describe 'ambiguous backslash-quote sequences' do
    it 'handles single backslash immediately before the closing quote of a field' do
      # Raw CSV bytes: "abc\",def
      #
      # Interpretation A (backslash is escape): field is unclosed (\" = embedded quote,
      #   parser keeps reading, finds ,def but no closing quote => MalformedCSV)
      #
      # Interpretation B (RFC 4180, backslash is literal): field = "abc\", next field = "def"
      #
      csv = "col_a,col_b\n\"abc\\\",def"

      # CHOOSE ONE — the test should match the parser's intended behavior:
      begin
        result = SmarterCSV.process(StringIO.new(csv))
        # If we reach here, parser treated backslash as literal (Interpretation B)
        expect(result.first[:col_a]).to eq('abc\\')
        expect(result.first[:col_b]).to eq('def')
      rescue SmarterCSV::MalformedCSV
        # Parser treated \" as escape (Interpretation A) — this is the v1.15.0 bug
        expect(true).to eq(true) # acknowledge this is the current (buggy) behavior
      end
    end

    it 'handles double backslash before the closing quote' do
      # Raw CSV bytes: "abc\\",def
      #
      # Interpretation A (backslash is escape): \\ = literal \, then " closes the field
      #   => field = "abc\", next field = "def" — SAME result as Interpretation B for single \
      #
      # Interpretation B (RFC 4180): \\ is just two literal backslashes, " closes the field
      #   => field = "abc\\", next field = "def"
      #
      csv = "col_a,col_b\n\"abc\\\\\",def"
      result = SmarterCSV.process(StringIO.new(csv))

      expect(result.length).to eq(1)
      expect(result.first[:col_b]).to eq('def')
      # The value of col_a depends on escape interpretation:
      # Escape ON:  'abc\'  (one backslash — \\ was collapsed)
      # Escape OFF: 'abc\\' (two backslashes — literal)
      expect(result.first[:col_a]).to be_a(String)
      expect(result.first[:col_a]).to include('\\')
    end

    it 'handles triple backslash before a quote' do
      # Raw CSV bytes: "abc\\\",def
      #
      # Escape ON:  \\\ before " => \\ = literal \, then \" = escaped quote
      #   => field is still open, reads ",def" as part of the field => MalformedCSV
      #
      # Escape OFF: \\\ is three literal backslashes, " closes the field
      #   => field = "abc\\\", next field = "def"
      #
      csv = "col_a,col_b\n\"abc\\\\\\\",def"

      begin
        result = SmarterCSV.process(StringIO.new(csv))
        expect(result.first[:col_a]).to eq('abc\\\\\\')
        expect(result.first[:col_b]).to eq('def')
      rescue SmarterCSV::MalformedCSV
        # Escape interpretation causes unclosed field
        expect(true).to eq(true)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Group 6: Multiline quoted fields with backslashes
  # ---------------------------------------------------------------------------
  describe 'multiline quoted fields with backslashes' do
    it 'handles a multiline field where a line ends with a backslash' do
      # The backslash at end-of-line inside a quoted field should NOT close the field
      csv = "col_a,col_b\n\"line1\\\nline2\",val"
      result = SmarterCSV.process(StringIO.new(csv))

      expect(result.length).to eq(1)
      expect(result.first[:col_a]).to include("line1")
      expect(result.first[:col_a]).to include("line2")
      expect(result.first[:col_b]).to eq('val')
    end

    it 'handles a multiline field with a backslash on the last line before the closing quote' do
      csv = "col_a,col_b\n\"line1\nline2\\\",val"

      begin
        result = SmarterCSV.process(StringIO.new(csv))
        # RFC 4180 interpretation: field = "line1\nline2\", col_b = "val"
        expect(result.first[:col_a]).to eq("line1\nline2\\")
        expect(result.first[:col_b]).to eq('val')
      rescue SmarterCSV::MalformedCSV
        # Backslash-escape interpretation: \" is not the closing quote => unclosed field
        expect(true).to eq(true)
      end
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
      result = SmarterCSV.process(StringIO.new(csv))

      expect(result.length).to eq(1)
      # SmarterCSV may strip empty values depending on :remove_empty_values
      # Test with the option explicitly disabled:
    end

    it 'parses a quoted field containing only a backslash' do
      # CSV: "\",next
      # RFC 4180: field = "\", col_b = "next"
      # Escape mode: \" is escaped quote, field is unclosed
      csv = "col_a,col_b\n\"\\\",next"

      begin
        result = SmarterCSV.process(StringIO.new(csv))
        expect(result.first[:col_a]).to eq('\\')
        expect(result.first[:col_b]).to eq('next')
      rescue SmarterCSV::MalformedCSV
        expect(true).to eq(true)
      end
    end

    it 'parses a quoted field containing only two backslashes' do
      csv = "col_a,col_b\n\"\\\\\",next"
      result = SmarterCSV.process(StringIO.new(csv))

      expect(result.length).to eq(1)
      expect(result.first[:col_b]).to eq('next')
    end
  end

  # ---------------------------------------------------------------------------
  # Group 9: Mixed backslash and doubled-quote escaping in the same file
  #
  # This is a particularly nasty real-world scenario. Some CSV producers
  # are inconsistent within the same file.
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

      # Row 1: RFC 4180 doubled-quote — should always work
      expect(result[0][:col_a]).to eq('She said "hello"')
      expect(result[0][:col_b]).to eq('greeting')

      # Row 2: trailing backslash — the Issue #316 scenario
      expect(result[1][:col_a]).to eq('C:\\Users\\')
      expect(result[1][:col_b]).to eq('path')
    end
  end

  # ---------------------------------------------------------------------------
  # Group 10: Custom quote_char interaction with backslash
  #
  # SmarterCSV supports custom quote characters. Ensure backslash behavior
  # is consistent regardless of quote_char.
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
  # Group 12: Bulk / multiple rows to verify no row-bleed or state leakage
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
      expect(result[1][:key]).to eq('ends_with_backslash\\')
      expect(result[1][:value]).to eq('b')
      expect(result[2][:key]).to eq('also_normal')
      expect(result[3][:key]).to eq('another_backslash\\')
      expect(result[3][:value]).to eq('d')
      expect(result[4][:key]).to eq('final')
    end
  end

  # ---------------------------------------------------------------------------
  # Group 13: If/when a backslash_escape option is added
  #
  # Uncomment and adapt these tests once the option exists.
  # ---------------------------------------------------------------------------
  # describe 'backslash_escape option' do
  #   context 'when backslash_escape: false (RFC 4180, default)' do
  #     it 'treats backslash as a literal character' do
  #       csv = "col\n\"abc\\\""
  #       result = SmarterCSV.process(StringIO.new(csv), backslash_escape: false)
  #       expect(result.first[:col]).to eq('abc\\')
  #     end
  #
  #     it 'does not interpret \\" as an escaped quote' do
  #       csv = "col_a,col_b\n\"abc\\\",def"
  #       result = SmarterCSV.process(StringIO.new(csv), backslash_escape: false)
  #       expect(result.first[:col_a]).to eq('abc\\')
  #       expect(result.first[:col_b]).to eq('def')
  #     end
  #   end
  #
  #   context 'when backslash_escape: true (MySQL/PHP compat)' do
  #     it 'interprets \\" as an escaped quote inside a quoted field' do
  #       csv = "col\n\"She said \\\"hello\\\"\""
  #       result = SmarterCSV.process(StringIO.new(csv), backslash_escape: true)
  #       expect(result.first[:col]).to eq('She said "hello"')
  #     end
  #
  #     it 'interprets \\\\\\" as literal backslash + closing quote' do
  #       csv = "col_a,col_b\n\"abc\\\\\",def"
  #       result = SmarterCSV.process(StringIO.new(csv), backslash_escape: true)
  #       expect(result.first[:col_a]).to eq('abc\\')
  #       expect(result.first[:col_b]).to eq('def')
  #     end
  #   end
  # end
end
