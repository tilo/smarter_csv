# frozen_string_literal: true

fixture_path = 'spec/fixtures'

[true, false].each do |bool|
  describe "handling files with escaped quote chars with#{bool ? ' C-' : 'out '}acceleration" do
    let(:options) { { acceleration: bool, quote_escaping: :backslash } }
    let(:reader) { SmarterCSV::Reader.new(file, options) }

    describe ".count_quote_chars with quote_escaping: :backslash" do
      let(:file) { 'something' }

      it "handles escaped characters and regular characters" do
        expect(reader.count_quote_chars("\"No\" \"Escaping\"", "\"", ",", :backslash)).to eq 4
        expect(reader.count_quote_chars("\"D\\\"Angelos\"", "\"", ",", :backslash)).to eq 2
        expect(reader.count_quote_chars("\!D\\\!Angelos\!", "\!", ",", :backslash)).to eq 2
      end
    end

    describe ".count_quote_chars with quote_escaping: :double_quotes" do
      let(:file) { 'something' }

      it "counts all quote chars without treating backslash as escape" do
        # No backslashes — same result either mode
        expect(reader.count_quote_chars("\"No\" \"Escaping\"", "\"", ",", :double_quotes)).to eq 4

        # Backslash-quote: in :double_quotes mode, backslash is literal, quote is counted
        # "D\"Angelos" has 3 quote chars (positions 0, 2, 10)
        expect(reader.count_quote_chars("\"D\\\"Angelos\"", "\"", ",", :double_quotes)).to eq 3

        # Custom quote char: \!D\\!\Angelos\! has 3 ! chars in :double_quotes mode
        # (in :backslash mode, the \! between D and Angelos is escaped, giving only 2)
        expect(reader.count_quote_chars("\!D\\\!Angelos\!", "\!", ",", :double_quotes)).to eq 3
      end
    end

    describe ".count_quote_chars_auto" do
      let(:file) { 'something' }

      it "returns [escaped_count, rfc_count] for dual counting" do
        # No backslashes — both counts are the same
        escaped, rfc = reader.count_quote_chars_auto("\"No\" \"Escaping\"", "\"", ",")
        expect(escaped).to eq 4
        expect(rfc).to eq 4

        # "D\"Angelos" — backslash-aware count skips the escaped quote
        escaped, rfc = reader.count_quote_chars_auto("\"D\\\"Angelos\"", "\"", ",")
        expect(escaped).to eq 2
        expect(rfc).to eq 3

        # "\",Y — backslash-aware: 0 (both quotes escaped-away or... let's trace)
        # chars: " \ " , Y
        # " -> rfc=1, escaped: not escaped -> escaped=1
        # \ -> escaped=true
        # " -> rfc=2, escaped: yes -> skip, escaped=false
        # , -> escaped=false
        # Y -> escaped=false
        escaped, rfc = reader.count_quote_chars_auto("\"\\\",Y", "\"", ",")
        expect(escaped).to eq 1
        expect(rfc).to eq 2
      end
    end

    context 'with quote_escaping: :backslash and escaped_quote_char.csv' do
      let(:file) { "#{fixture_path}/escaped_quote_char.csv" }

      it 'loads the csv file without issues' do
        data = reader.process

        expect(data[0]).to eq(
          content: 'Some content',
          escapedname: "D\\\"Angelos",
          othercontent: "Some More Content"
        )
        expect(data[1]).to eq(
          content: 'Some content',
          escapedname: "O\\\"heard",
          othercontent: "Some More Content\\\\"
        )
        expect(data.size).to eq 2
      end
    end

    context 'with quote_escaping: :backslash and custom quote_char' do
      let(:file) { "#{fixture_path}/escaped_quote_char_2.csv" }
      let(:options) do
        { quote_char: "!", acceleration: bool, quote_escaping: :backslash }
      end

      it 'loads the csv file without issues' do
        data = reader.process

        expect(data[0]).to eq(
          content: 'Some content',
          escapedname: "D\\\!Angelos",
          othercontent: "Some More Content"
        )
        expect(data[1]).to eq(
          content: 'Some content',
          escapedname: "O\\\!heard",
          othercontent: "Some More Content\\\\"
        )
        expect(data.size).to eq 2
      end
    end

    context 'with quote_escaping: :backslash and escaped_quote_char_3.csv' do
      let(:file) { "#{fixture_path}/escaped_quote_char_3.csv" }

      it 'loads the csv file without issues' do
        data = reader.process

        expect(data[0]).to eq(
          content: '\\"Some content\\"',
          escapedname: "D\\\"Angelos",
          othercontent: '\\"Some More Content\\"'
        )
        expect(data[1]).to eq(
          content: '\\"Some content\\"',
          escapedname: "O\\\"heard",
          othercontent: '\\"Some More Content\\"'
        )
        expect(data.size).to eq 2
      end
    end

    context 'with quote_escaping: :backslash and custom single-quote quote_char' do
      let(:file) { "#{fixture_path}/escaped_quote_char_4.csv" }
      let(:options) do
        { quote_char: "'", acceleration: bool, quote_escaping: :backslash }
      end

      it 'loads the csv file without issues' do
        data = reader.process

        expect(data[0]).to eq(
          content: "\\'Some content\\'",
          escapedname: "D\\\'Angelos",
          othercontent: "\\'Some More Content\\'"
        )
        expect(data[1]).to eq(
          content: "\\'Some content\\'",
          escapedname: "O\\\'heard",
          othercontent: "Some \\\\ More \\\\ Content\\\\"
        )
        expect(data.size).to eq 2
      end
    end
  end
end
