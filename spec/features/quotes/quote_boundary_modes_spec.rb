# frozen_string_literal: true

# Tests the user-facing contract of SmarterCSV.process for inputs containing
# stray (non-doubled) quote characters in fields.
#
# Project philosophy: permissive parsing of real-world CSV data. Heights like
# `6'2"`, measurements like `5"4'`, names with stray quote marks — these
# should parse cleanly in the default `:standard` quote_boundary mode.
#
# `:legacy` mode is the explicit opt-in for strict RFC 4180 — there, stray
# quote_chars in mid-field positions are an error (the line is rejected).
#
# Both the C-accelerated path and the Ruby fallback path MUST agree on
# every input across both modes — no divergence between paths is acceptable.
#
# These tests run through `SmarterCSV.process` (the user-facing API), NOT
# through the internal `parse` method, because the contract that matters is
# what library users actually observe.

describe "quote_boundary modes via SmarterCSV.process" do
  # Helper: parse a single CSV data row with synthesized headers and return
  # field values as a plain Array. Disables process's default transformations
  # so output is raw strings comparable to the input field content.
  def fields_via_process(line, quote_boundary:, acceleration:)
    hdrs = (1..20).map { |i| :"c#{i}" }
    io = StringIO.new("#{line}\n")
    opts = {
      user_provided_headers: hdrs,
      headers_in_file: false,
      remove_empty_values: false,
      convert_values_to_numeric: false,
      quote_boundary: quote_boundary,
      acceleration: acceleration,
    }
    rows = SmarterCSV.process(io, opts)
    return [] if rows.empty?

    vals = hdrs.map { |h| rows.first[h] }
    vals.pop while !vals.empty? && vals.last.nil?
    vals
  end

  # ============================================================================
  # Run all assertions under both the C-accelerated and Ruby fallback paths.
  # Any divergence between the two is a regression.
  # ============================================================================
  [true, false].each do |accel|
    path_label = accel ? "C-accelerated" : "Ruby fallback"

    describe "#{path_label} path" do
      # --------------------------------------------------------------------
      # Well-formed inputs: must behave identically in :standard AND :legacy.
      # If these ever diverge, something is fundamentally wrong.
      # --------------------------------------------------------------------
      describe "well-formed inputs (identical in both quote_boundary modes)" do
        [
          ['plain unquoted',          'hello,world,foo',                       %w[hello world foo]],
          ['plain quoted',            '"hello","world","foo"',                 %w[hello world foo]],
          ['UTF-8 multi-byte quoted', '"Tōkyō","São Paulo","Zürich"', ['Tōkyō', 'São Paulo', 'Zürich']],
          ['doubled quotes inside',   '"a""b","c""d","x"', ['a"b', 'c"d', 'x']],
          ['issue #334: doubled quote immediately followed by comma inside quoted field',
           'A4,"Width: 8.27"", Height: 11.69""",1',
           ['A4', 'Width: 8.27", Height: 11.69"', '1']],
          ['issue #334: embedded quoted phrase immediately followed by comma inside quoted field',
           'A,"He said ""Hi"", then left",2',
           ['A', 'He said "Hi", then left', '2']],
          ['issue #334: doubled quote immediately before col_sep',     '"a""",b',     ['a"', 'b']],
          ['issue #334: doubled quote as last field, before EOL',      'a,"hello"""', ['a', 'hello"']],
          ['issue #334: consecutive doubled quotes inside field',      '"a""""b",z',  ['a""b', 'z']],
          ['issue #334: doubled quote at field start',                 '"""x",z',     ['"x', 'z']],
          ['apostrophes (not quote_char)', "name,5'11,O'Brian",                ['name', "5'11", "O'Brian"]],
          ['empty quoted',            '"",a,""',                               ['', 'a', '']],
        ].each do |label, input, expected|
          %i[standard legacy].each do |qb|
            it "#{label} parses identically in :#{qb} mode" do
              expect(fields_via_process(input, quote_boundary: qb, acceleration: accel))
                .to eq(expected)
            end
          end
        end
      end

      # --------------------------------------------------------------------
      # :standard mode is permissive — these REAL-WORLD inputs must work.
      # The library's job is to handle slightly-incorrect CSV gracefully.
      # --------------------------------------------------------------------
      describe ":standard mode accepts mid-field stray quote_chars as literal content" do
        # Height notation: 5'11 = five feet eleven inches (apostrophe is feet, " is inches)
        it 'parses height with stray inch-mark — `5"11`' do
          expect(fields_via_process('name,5"11,note', quote_boundary: :standard, acceleration: accel))
            .to eq(['name', '5"11', 'note'])
        end

        it %(parses height with stray inch and feet — `5"4'`) do
          line = %q[name,5"4',note]
          expect(fields_via_process(line, quote_boundary: :standard, acceleration: accel))
            .to eq(['name', %q(5"4'), 'note'])
        end

        it %(parses trailing inch-mark — `6'2"` at field end) do
          line = %q[name,6'2",note]
          expect(fields_via_process(line, quote_boundary: :standard, acceleration: accel))
            .to eq(['name', %q(6'2"), 'note'])
        end

        # Lock in the real-world Schwarzenegger row (matches malformed_data_gobbled.csv).
        it "parses a complete real-world height row" do
          line = %q[Arnold Schwarzenegger,1947-07-30,6'2"]
          expect(fields_via_process(line, quote_boundary: :standard, acceleration: accel))
            .to eq(['Arnold Schwarzenegger', '1947-07-30', %q(6'2")])
        end

        # Furniture/dimension notation: 49.2" L x 49.2" W ...
        it "parses furniture dimensions with stray inch-marks" do
          line = 'Indoor Chrome,49.2" L x 49.2" W,Chrome'
          expect(fields_via_process(line, quote_boundary: :standard, acceleration: accel))
            .to eq(['Indoor Chrome', '49.2" L x 49.2" W', 'Chrome'])
        end

        # Issue #334 compatibility: a malformed terminal "" (doubled quote with no
        # content after the pair) is treated leniently — the final quote closes the
        # field rather than turning the row into an unclosed-quote error. This is the
        # historical behavior the doubled-quote fix deliberately preserves.
        it %(accepts a malformed terminal `""` leniently — `"b""` → `b"`) do
          expect(fields_via_process('a,"b""', quote_boundary: :standard, acceleration: accel))
            .to eq(['a', 'b"'])
        end
      end

      # --------------------------------------------------------------------
      # :legacy mode rejects the same inputs (strict RFC 4180). This is the
      # explicit opt-in for users who want strictness.
      # --------------------------------------------------------------------
      describe ":legacy mode rejects mid-field stray quote_chars" do
        it 'rejects `5"11` height notation' do
          expect do
            fields_via_process('name,5"11,note', quote_boundary: :legacy, acceleration: accel)
          end.to raise_error(SmarterCSV::MalformedCSV)
        end

        it %(rejects trailing inch-mark `6'2"`) do
          expect do
            fields_via_process(%q[name,6'2",note], quote_boundary: :legacy, acceleration: accel)
          end.to raise_error(SmarterCSV::MalformedCSV)
        end

        it "rejects a complete real-world height row" do
          line = %q[Arnold Schwarzenegger,1947-07-30,6'2"]
          expect do
            fields_via_process(line, quote_boundary: :legacy, acceleration: accel)
          end.to raise_error(SmarterCSV::MalformedCSV)
        end

        # Counterpart to the :standard leniency above: strict mode rejects the
        # malformed terminal "" instead of recovering from it.
        it %(rejects a malformed terminal `""` — `"b""`) do
          expect do
            fields_via_process('a,"b""', quote_boundary: :legacy, acceleration: accel)
          end.to raise_error(SmarterCSV::MalformedCSV)
        end
      end

      # --------------------------------------------------------------------
      # Encoding invariant: result strings must carry the input encoding tag.
      # Tested under :standard mode (the user-facing default) because that's
      # the mode that handles real-world stray-quote data.
      # --------------------------------------------------------------------
      describe "encoding preservation in :standard mode" do
        it "preserves UTF-8 encoding on stray-quote real-world data" do
          line = 'Tōkyō,5"11,note'
          fields = fields_via_process(line, quote_boundary: :standard, acceleration: accel)
          expect(fields).to eq(['Tōkyō', '5"11', 'note'])
          fields.each do |f|
            expect(f.encoding).to eq(Encoding::UTF_8), "expected UTF-8, got #{f.encoding} for #{f.inspect}"
            expect(f.valid_encoding?).to be(true)
          end
        end
      end

      # --------------------------------------------------------------------
      # Mutability invariant: result strings must not be frozen — users
      # commonly do `row[:name] << ...` and similar in-place mutation.
      # --------------------------------------------------------------------
      describe "mutability in :standard mode" do
        it "result strings from stray-quote fields are not frozen" do
          fields = fields_via_process('name,5"11,note', quote_boundary: :standard, acceleration: accel)
          fields.each { |f| expect(f.frozen?).to be(false), "#{f.inspect} should be mutable" }
        end
      end
    end
  end

  # ============================================================================
  # Cross-path divergence detection.
  # For each test input, the C path and the Ruby path must produce the same
  # result (same value OR same kind of error). If they diverge, that's a bug.
  # ============================================================================
  describe "C-accelerated and Ruby fallback produce identical results" do
    SHARED_INPUTS = [
      'hello,world,foo',
      '"hello","world","foo"',
      '"Tōkyō","São Paulo","Zürich"',
      '"a""b","c""d","x"',
      "name,5'11,O'Brian",
      'name,5"11,note',
      %q[name,5"4',note],
      %q[name,6'2",note],
      %q[Arnold Schwarzenegger,1947-07-30,6'2"],
      'A4,"Width: 8.27"", Height: 11.69""",1',
      'A,"He said ""Hi"", then left",2',
      '"a""",b',
      'a,"hello"""',
      '"a""""b",z',
      '"""x",z',
      'a,"b""',
    ].freeze

    SHARED_INPUTS.each do |input|
      %i[standard legacy].each do |qb|
        it "C path and Ruby path agree on #{input.inspect} (qb=#{qb})" do
          c_result = begin
            [:ok, fields_via_process(input, quote_boundary: qb, acceleration: true)]
          rescue SmarterCSV::Error => e
            [:raise, e.class]
          end
          rb_result = begin
            [:ok, fields_via_process(input, quote_boundary: qb, acceleration: false)]
          rescue SmarterCSV::Error => e
            [:raise, e.class]
          end
          expect(c_result).to eq(rb_result), "C: #{c_result.inspect}\nRb: #{rb_result.inspect}"
        end
      end
    end
  end
end
