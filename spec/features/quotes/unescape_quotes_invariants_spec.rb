# frozen_string_literal: true

# Invariants that must hold for quoted-field handling across both the
# C-accelerated and Ruby-fallback paths.
#
# These tests intentionally assert on properties that the existing byte-content
# tests do not cover:
#
#   1. Encoding tag of result strings (existing tests compare values, which
#      pass even when the encoding pointer is subtly wrong).
#   2. Frozen state of result strings (must be mutable so user code can
#      `row[:name].strip!`, `<<`, etc.).
#   3. Behavior on long quoted fields (>23 bytes) that exercise Ruby's
#      heap-content allocation path rather than the embedded-string path.
#
# Why these exist: any change to `unescape_quotes` in the C extension —
# including the "fast path when no doubled quotes are present" optimization —
# must preserve all three invariants. The pre-existing tests would not catch
# regressions on encoding-tag or frozen-state.

class QuoteInvariantsHarness
  include SmarterCSV::Parser

  # Mimic the relevant part of Reader#initialize so the Parser methods can read the
  # cached @quote_char / @doubled_quote_chars ivars directly — same as in production.
  def initialize(options = {})
    @quote_char = options[:quote_char] || '"'
    @doubled_quote_chars = @quote_char * 2
  end

  def has_acceleration
    !!SmarterCSV::Parser.respond_to?(:parse_csv_line_c)
  end
end

[true, false].each do |acceleration|
  describe "quoted-field invariants with#{acceleration ? ' C-' : 'out '}acceleration" do
    let(:options) { {col_sep: ',', row_sep: "\n", quote_char: '"', acceleration: acceleration } }
    let(:parser) { QuoteInvariantsHarness.new(options) }

    # ----------------------------------------------------------------------
    # 1. Encoding tag preservation
    # ----------------------------------------------------------------------
    describe "preserves the input encoding tag on result strings" do
      it "returns UTF-8 strings for UTF-8 input with quoted ASCII fields" do
        line = '"hello","world","foo"'.dup.force_encoding(Encoding::UTF_8)
        array, _size = parser.send(:parse, line, options)
        expect(array).to eq %w[hello world foo]
        array.each do |s|
          expect(s.encoding).to eq(Encoding::UTF_8), "expected UTF-8, got #{s.encoding}"
        end
      end

      it "returns UTF-8 strings for UTF-8 input with multi-byte content inside quotes" do
        # "Tōkyō" — the ō is a 2-byte UTF-8 sequence (C5 8D).
        # "São Paulo" — ã is 2-byte UTF-8.
        line = '"Tōkyō","São Paulo","Zürich"'.dup.force_encoding(Encoding::UTF_8)
        array, _size = parser.send(:parse, line, options)
        expect(array).to eq ['Tōkyō', 'São Paulo', 'Zürich']
        array.each do |s|
          expect(s.encoding).to eq(Encoding::UTF_8)
          expect(s.valid_encoding?).to be(true)
        end
      end

      it "returns UTF-8 strings for quoted fields with doubled quotes inside (slow path)" do
        # Doubled quote inside; exercises the slow path of unescape_quotes.
        line = '"He said ""hello""","world"'.dup.force_encoding(Encoding::UTF_8)
        array, _size = parser.send(:parse, line, options)
        expect(array).to eq ['He said "hello"', 'world']
        array.each { |s| expect(s.encoding).to eq(Encoding::UTF_8) }
      end

      it "preserves ASCII-8BIT encoding when input is binary" do
        line = '"alpha","beta"'.b
        array, _size = parser.send(:parse, line, options)
        expect(array).to eq %w[alpha beta]
        array.each do |s|
          expect(s.encoding).to eq(Encoding::ASCII_8BIT)
        end
      end
    end

    # ----------------------------------------------------------------------
    # 2. Mutability of result strings
    # ----------------------------------------------------------------------
    describe "returns mutable (non-frozen) strings" do
      it "result strings from quoted fields are mutable" do
        line = '"alpha","beta","gamma"'
        array, _size = parser.send(:parse, line, options)
        array.each do |s|
          expect(s.frozen?).to be(false), "expected #{s.inspect} to be mutable"
        end
      end

      it "result strings from quoted fields with doubled quotes are mutable (slow path)" do
        line = '"a""b","c""d"'
        array, _size = parser.send(:parse, line, options)
        expect(array).to eq ['a"b', 'c"d']
        array.each { |s| expect(s.frozen?).to be(false) }
      end

      it "result strings from unquoted fields with stray quote chars are mutable" do
        # Liberal-parsing case: unquoted field contains a quote char in the middle.
        # The slow path goes through unescape_quotes via the `memchr(...)` branch.
        line = 'is,this "three or four",fields'
        array, _size = parser.send(:parse, line, options)
        expect(array).to eq ['is', 'this "three or four"', 'fields']
        array.each { |s| expect(s.frozen?).to be(false) }
      end

      it "user can mutate a result string without affecting later parses" do
        line = '"alpha","beta"'
        array1, _ = parser.send(:parse, line, options)
        array1[0] << "_suffix"
        array2, _ = parser.send(:parse, line, options)
        expect(array2[0]).to eq('alpha')
      end
    end

    # ----------------------------------------------------------------------
    # 3. Long quoted fields (>23 bytes — heap-content path)
    # ----------------------------------------------------------------------
    describe "long quoted fields (>23 bytes)" do
      it "round-trips a long quoted field with no doubled quotes" do
        long_value = 'A' * 100
        line = %{"prefix","#{long_value}","suffix"}
        array, _size = parser.send(:parse, line, options)
        expect(array).to eq ['prefix', long_value, 'suffix']
        expect(array[1].bytesize).to eq(100)
        expect(array[1].encoding).to eq(line.encoding)
        expect(array[1].frozen?).to be(false)
      end

      it "round-trips a long quoted field with one doubled quote in the middle" do
        # Quote at position 50 of a 100-byte field. Exercises both:
        #   - The heap-content allocation path (length > 23)
        #   - The doubled-quote handling in unescape_quotes (full slow path)
        prefix = 'a' * 50
        suffix = 'b' * 49
        long_value = "#{prefix}\"#{suffix}" # 100 bytes, embedded "
        line = %{"prefix","#{prefix}""#{suffix}","suffix"}
        array, _size = parser.send(:parse, line, options)
        expect(array).to eq ['prefix', long_value, 'suffix']
        expect(array[1].bytesize).to eq(100)
      end

      it "round-trips a long quoted field with multiple doubled quotes" do
        # Three doubled quotes scattered through a long field.
        long_value = 'x' * 20 + '"' + 'y' * 20 + '"' + 'z' * 20 + '"' + 'w' * 20
        raw = ('x' * 20 + '""' + 'y' * 20 + '""' + 'z' * 20 + '""' + 'w' * 20)
        line = %{"#{raw}","end"}
        array, _size = parser.send(:parse, line, options)
        expect(array).to eq [long_value, 'end']
        expect(array[0].bytesize).to eq(83) # 4×20 + 3 quote chars
      end

      it "round-trips a long quoted UTF-8 field with multi-byte content" do
        # Each "ä" is 2 bytes UTF-8; 30 × 2 = 60 bytes, >23.
        long_value = 'ä' * 30
        line = %{"start","#{long_value}","end"}.dup.force_encoding(Encoding::UTF_8)
        array, _size = parser.send(:parse, line, options)
        expect(array).to eq ['start', long_value, 'end']
        expect(array[1].bytesize).to eq(60)
        expect(array[1].encoding).to eq(Encoding::UTF_8)
        expect(array[1].valid_encoding?).to be(true)
      end

      it "round-trips a long quoted field that is exactly 23 bytes (embedded-string boundary)" do
        boundary = 'b' * 23
        line = %{"x","#{boundary}","y"}
        array, _size = parser.send(:parse, line, options)
        expect(array).to eq ['x', boundary, 'y']
        expect(array[1].bytesize).to eq(23)
        expect(array[1].frozen?).to be(false)
      end

      it "round-trips a long quoted field that is 24 bytes (just past embedded boundary)" do
        beyond = 'c' * 24
        line = %{"x","#{beyond}","y"}
        array, _size = parser.send(:parse, line, options)
        expect(array).to eq ['x', beyond, 'y']
        expect(array[1].bytesize).to eq(24)
        expect(array[1].frozen?).to be(false)
      end
    end

    # ----------------------------------------------------------------------
    # 4. Robustness: stray (non-doubled) quote chars inside an outer-quoted field
    # ----------------------------------------------------------------------
    #
    # SmarterCSV intentionally accepts slightly malformed CSV where a quoted field
    # contains stray (non-doubled) quote characters inside. The first-and-last-byte
    # heuristic treats the field as quoted, strips the outer quotes, and emits the
    # inner content as-is (no unescaping needed since there are no doubled pairs).
    #
    # This is the exact case the unescape_quotes short-circuit optimization targets:
    # pre-scan finds no doubled pair, so the field is emitted directly via
    # rb_enc_str_new without the temp buffer walk. The tests below lock in the
    # robustness contract.
    #
    # NOTE: when both stray and doubled quotes coexist in the same field
    # (e.g. `"a""b"c"`), the state machine picks RFC 4180 interpretation and
    # may raise MalformedCSV. That's an ambiguous case, intentionally not covered
    # as "robust" — see the comment block above for the boundary.
    describe "stray (non-doubled) quote chars inside outer-quoted field" do
      it "passes through one stray quote inside a quoted field" do
        line = '"abc"def"ghi",x'
        array, _size = parser.send(:parse, line, options)
        expect(array).to eq ['abc"def"ghi', 'x']
        expect(array[0].frozen?).to be(false)
      end

      it "passes through multiple stray quotes inside a quoted field" do
        line = '"a"b"c","y"'
        array, _size = parser.send(:parse, line, options)
        expect(array).to eq ['a"b"c', 'y']
      end

      it "passes through stray quotes in the trailing field of a row" do
        line = '"plain","mixed "with" stray"'
        array, _size = parser.send(:parse, line, options)
        expect(array).to eq ['plain', 'mixed "with" stray']
      end

      it "preserves encoding on a quoted field with stray quotes inside" do
        line = '"Tōkyō"Ōsaka"Kyoto",end'.dup.force_encoding(Encoding::UTF_8)
        array, _size = parser.send(:parse, line, options)
        expect(array).to eq ['Tōkyō"Ōsaka"Kyoto', 'end']
        expect(array[0].encoding).to eq(Encoding::UTF_8)
        expect(array[0].valid_encoding?).to be(true)
      end

      it "passes through a long quoted field with stray quotes (heap-content path)" do
        # >23 bytes so we exercise the heap-content branch. EVEN number of stray quotes
        # (two) is required — SmarterCSV's robust-pass-through behavior depends on the
        # state machine toggling in/out of quoted mode an even number of times before
        # the col_sep. With one stray the parser errors with MalformedCSV.
        long = "#{'a' * 30}\"#{'b' * 30}\"#{'c' * 30}" # 92 bytes, 2 stray quotes
        line = %{"#{long}","end"}
        array, _size = parser.send(:parse, line, options)
        expect(array).to eq [long, 'end']
        expect(array[0].bytesize).to eq(92)
      end

      it "signals incomplete via [[], -1] when stray quote count is odd, on both paths" do
        # Both C and Ruby paths signal "incomplete — needs more data" via [[], -1]
        # when the field's quote chars are unbalanced. The Reader's stitch loop
        # consumes this signal: it appends the next physical line and re-parses, or
        # eventually raises MalformedCSV at EOF if the field never closes.
        #
        # NOTE: via the user-facing `SmarterCSV.process` API, `quote_boundary: :standard`
        # is the default and mid-field stray quotes are treated as literal content.
        # This test exercises the lower-level `parse` method, which sees legacy
        # semantics when called directly (no process_options pipeline), so unbalanced
        # quotes ARE treated as unclosed at this layer.
        #
        # Historical note: prior to the alignment, the C array-variant raised
        # MalformedCSV here while the Ruby fallback returned [[], -1] — an internal
        # inconsistency. Both paths now signal uniformly, matching the hash-variant
        # C function which has always returned data_size = -1 for this condition.
        line = '"abc"def","end"' # 3 quote chars in first field: opens, closes, opens-without-close
        expect(parser.send(:parse, line, options)).to eq([[], -1])
      end
    end

    # ----------------------------------------------------------------------
    # 5. Result strings from each call are independent objects
    # ----------------------------------------------------------------------
    describe "result strings are independent objects across calls" do
      it "two parses of the same line return distinct string instances" do
        line = '"alpha","beta"'
        a1, _ = parser.send(:parse, line, options)
        a2, _ = parser.send(:parse, line, options)
        expect(a1[0]).to eq(a2[0])
        expect(a1[0].object_id).not_to eq(a2[0].object_id)
      end

      it "two distinct fields with the same content are distinct string instances" do
        # If a future optimization shares string objects for repeated content,
        # this test will need to be updated — but only after a deliberate
        # decision to do so (e.g., frozen-string-dedup output).
        line = '"same","same"'
        array, _ = parser.send(:parse, line, options)
        expect(array[0]).to eq(array[1])
        expect(array[0].object_id).not_to eq(array[1].object_id)
      end
    end
  end
end
