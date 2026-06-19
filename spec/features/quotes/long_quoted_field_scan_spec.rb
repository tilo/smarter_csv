# frozen_string_literal: true

# Coverage for the bulk "skip to the next interesting byte" scan inside quoted fields.
#
# smarter_csv already skips quoted-field content with memchr in RFC mode (the C
# extension's Opt #6, around smarter_csv.c:1157 / :1651), and the SIMD scanner handoff
# note proposes a later NEON "quote-OR-backslash" scan for quote_escaping: :backslash
# mode. Both only do anything on LONG quoted content, and a bulk-skip bug would only
# show up when the interesting byte (a quote or a backslash) lands at offsets straddling
# a 16-byte SIMD chunk boundary.
#
# The existing specs cover RFC-mode long fields (unescape_quotes_invariants_spec) and
# SHORT backslash-mode fields (backslash_in_quoted_field_spec). This file fills the gap:
# LONG fields, in :backslash mode (and a few RFC cases), with the interesting byte placed
# at offsets that straddle the 16-byte boundary. Output must be byte-identical on the C
# and Ruby paths, so every case runs under both via the [true, false].each parity loop.

# Offsets chosen to straddle the 16- and 32-byte NEON chunk boundaries (and a couple
# inside the scalar tail), so an off-by-one in any future vectorized scan is caught.
BOUNDARY_OFFSETS = [13, 14, 15, 16, 17, 18, 30, 31, 32, 33, 34].freeze

[true, false].each do |acceleration|
  describe "long quoted-field scan with#{acceleration ? ' C-' : 'out '}acceleration" do
    bs = "\\" # a single backslash
    q  = '"'  # the quote char

    # =========================================================================
    # quote_escaping: :backslash — a \" escape sitting at chunk-boundary offsets.
    # The \" must stay literal (backslash NOT stripped — see backslash_in_quoted_field_spec)
    # and the field must close at the later, unescaped quote.
    # =========================================================================
    context 'backslash mode: \\" escape straddling a 16-byte boundary' do
      BOUNDARY_OFFSETS.each do |offset|
        it "keeps the \\\" literal and closes at the real quote (escape at offset #{offset})" do
          content = ('a' * offset) + bs + q + ('b' * 20)
          csv = "a,b\n" + q + content + q + ",Z\n"
          data = SmarterCSV.process(StringIO.new(csv), acceleration: acceleration, quote_escaping: :backslash)
          expect(data.size).to eq 1
          expect(data[0][:a]).to eq content
          expect(data[0][:b]).to eq 'Z'
        end
      end
    end

    # =========================================================================
    # quote_escaping: :backslash — a trailing backslash run right before the closing
    # quote, with the run straddling a chunk boundary. Even count → quote closes;
    # odd count → the closing quote is escaped, so the field is unclosed (MalformedCSV).
    # =========================================================================
    context 'backslash mode: trailing backslash run before the closing quote' do
      BOUNDARY_OFFSETS.each do |prefix_len|
        it "even backslash count closes the field (prefix #{prefix_len})" do
          content = ('a' * prefix_len) + bs + bs # ends with two backslashes → even
          csv = "a,b\n" + q + content + q + ",Z\n"
          data = SmarterCSV.process(StringIO.new(csv), acceleration: acceleration, quote_escaping: :backslash)
          expect(data.size).to eq 1
          expect(data[0][:a]).to eq content
          expect(data[0][:b]).to eq 'Z'
        end

        it "odd backslash count escapes the closing quote → MalformedCSV (prefix #{prefix_len})" do
          content = ('a' * prefix_len) + bs # single trailing backslash → odd
          csv = "a,b\n" + q + content + q + ",Z\n"
          expect {
            SmarterCSV.process(StringIO.new(csv), acceleration: acceleration, quote_escaping: :backslash)
          }.to raise_error(SmarterCSV::MalformedCSV)
        end
      end
    end

    # =========================================================================
    # quote_escaping: :backslash — long content that also contains a separator and an
    # embedded newline (multiline stitch). A backslash is present so Opt #5 does NOT
    # downgrade to RFC mode; this keeps the line on the backslash slow path.
    # =========================================================================
    context 'backslash mode: long content with embedded separator and newline' do
      it 'keeps a separator inside the quoted field as content' do
        content = ('a' * 20) + ',' + ('b' * 20) + bs + q + ('c' * 20)
        csv = "a,b\n" + q + content + q + ",Z\n"
        data = SmarterCSV.process(StringIO.new(csv), acceleration: acceleration, quote_escaping: :backslash)
        expect(data.size).to eq 1
        expect(data[0][:a]).to eq content
        expect(data[0][:b]).to eq 'Z'
      end

      it 'stitches an embedded newline inside the long quoted field' do
        content = ('a' * 20) + bs + q + ('b' * 20) + "\n" + ('c' * 20)
        csv = "a,b\n" + q + content + q + ",Z\n"
        data = SmarterCSV.process(StringIO.new(csv), acceleration: acceleration, quote_escaping: :backslash)
        expect(data.size).to eq 1
        expect(data[0][:a]).to eq content
        expect(data[0][:b]).to eq 'Z'
      end
    end

    # =========================================================================
    # quote_escaping: :backslash + multi-char col_sep on long content. Multi-char sep
    # forces the slow path; the sep inside the quotes must be treated as content.
    # =========================================================================
    context 'backslash mode: multi-char col_sep on long content' do
      it 'treats the multi-char separator inside quotes as content' do
        content = ('a' * 20) + '::' + ('b' * 20) + bs + q + ('c' * 20)
        csv = "a::b\n" + q + content + q + "::Z\n"
        data = SmarterCSV.process(StringIO.new(csv), acceleration: acceleration, quote_escaping: :backslash, col_sep: '::')
        expect(data.size).to eq 1
        expect(data[0][:a]).to eq content
        expect(data[0][:b]).to eq 'Z'
      end
    end

    # =========================================================================
    # RFC mode (:double_quotes) on long content — guards the already-shipped memchr
    # skip (Opt #6): the bulk skip must not lose a separator or a newline inside quotes.
    # =========================================================================
    context 'RFC mode: long content with embedded separator and newline' do
      it 'keeps commas inside a long quoted field as content' do
        content = ('a' * 20) + ',' + ('b' * 20) + ',' + ('c' * 20)
        csv = "a,b\n" + q + content + q + ",Z\n"
        data = SmarterCSV.process(StringIO.new(csv), acceleration: acceleration, quote_escaping: :double_quotes)
        expect(data.size).to eq 1
        expect(data[0][:a]).to eq content
        expect(data[0][:b]).to eq 'Z'
      end

      it 'stitches an embedded newline inside a long quoted field' do
        content = ('a' * 30) + "\n" + ('b' * 30)
        csv = "a,b\n" + q + content + q + ",Z\n"
        data = SmarterCSV.process(StringIO.new(csv), acceleration: acceleration, quote_escaping: :double_quotes)
        expect(data.size).to eq 1
        expect(data[0][:a]).to eq content
        expect(data[0][:b]).to eq 'Z'
      end

      it 'collapses a doubled quote that straddles the 16-byte boundary' do
        # Doubled "" near the chunk boundary → single " in the value.
        content_raw = ('a' * 15) + '""' + ('b' * 20)
        content_val = ('a' * 15) + '"'  + ('b' * 20)
        csv = "a,b\n" + q + content_raw + q + ",Z\n"
        data = SmarterCSV.process(StringIO.new(csv), acceleration: acceleration, quote_escaping: :double_quotes)
        expect(data.size).to eq 1
        expect(data[0][:a]).to eq content_val
        expect(data[0][:b]).to eq 'Z'
      end
    end
  end
end

# =========================================================================
# Explicit C-vs-Ruby parity sweep on the trickiest long-field combinations. If a
# future SIMD port changes only the C path, any divergence on long content trips here.
# =========================================================================
describe 'long quoted-field scan: C and Ruby paths agree' do
  bs = "\\"
  q  = '"'

  scenarios = []
  BOUNDARY_OFFSETS.each do |offset|
    scenarios << ["a,b\n" + q + ('a' * offset) + bs + q + ('b' * 20) + q + ",Z\n", { quote_escaping: :backslash }]
    scenarios << ["a,b\n" + q + ('a' * offset) + bs + bs + q + ",Z\n", { quote_escaping: :backslash }]
  end
  scenarios << ["a,b\n" + q + ('a' * 20) + bs + q + ('b' * 20) + "\n" + ('c' * 20) + q + ",Z\n", { quote_escaping: :backslash }]
  scenarios << ["a::b\n" + q + ('a' * 20) + '::' + ('b' * 20) + bs + q + ('c' * 20) + q + "::Z\n", { quote_escaping: :backslash, col_sep: '::' }]

  scenarios.each_with_index do |(csv, opts), idx|
    it "scenario #{idx} (#{opts.inspect}) parses identically on both paths" do
      c_data    = SmarterCSV.process(StringIO.new(csv), **opts.merge(acceleration: true))
      ruby_data = SmarterCSV.process(StringIO.new(csv), **opts.merge(acceleration: false))
      expect(c_data).to eq(ruby_data), "C/Ruby mismatch for #{csv.inspect}"
    end
  end
end
