# frozen_string_literal: true

fixture_path = 'spec/fixtures'

[true, false].each do |bool|
  describe "handling files with escaped quote chars with#{bool ? ' C-' : 'out '}acceleration" do
    let(:options) { { acceleration: bool } }

    describe ".count_quote_chars" do
      it "handles escaped characters and regular characters" do
        expect(SmarterCSV.count_quote_chars("\"No\" \"Escaping\"", "\"")).to eq 4
        expect(SmarterCSV.count_quote_chars("\"D\\\"Angelos\"", "\"")).to eq 2
        expect(SmarterCSV.count_quote_chars("\!D\\\!Angelos\!", "\!")).to eq 2
      end

      # Test with different quote characters: ", ', and !
      ['"', "'", '!'].each do |quote_char|
        context "with quote character '#{quote_char}'" do
          it "counts unescaped #{quote_char} characters" do
            expect(SmarterCSV.count_quote_chars("a#{quote_char}bc#{quote_char}d", quote_char)).to eq(2)
          end

          it "does not count escaped #{quote_char} characters" do
            expect(SmarterCSV.count_quote_chars("a\\#{quote_char}bc#{quote_char}d", quote_char)).to eq(1)
          end

          it "handles strings with only escaped #{quote_char} characters" do
            expect(SmarterCSV.count_quote_chars("\\#{quote_char}\\#{quote_char}\\#{quote_char}", quote_char)).to eq(0)
          end

          it "handles strings with mixed escaped and unescaped #{quote_char} characters" do
            expect(SmarterCSV.count_quote_chars("#{quote_char}\\#{quote_char}#{quote_char}\\#{quote_char}#{quote_char}", quote_char)).to eq(3)
          end
        end
      end

      # Edge cases
      context 'with edge cases' do
        it 'returns 0 for nil line' do
          expect(SmarterCSV.count_quote_chars(nil, '"')).to eq(0)
        end

        it 'returns 0 for nil quote character' do
          expect(SmarterCSV.count_quote_chars('some text', nil)).to eq(0)
        end

        it 'returns 0 for empty quote character' do
          expect(SmarterCSV.count_quote_chars('some text', '')).to eq(0)
        end

        it 'returns 0 for empty line' do
          expect(SmarterCSV.count_quote_chars('', '"')).to eq(0)
        end

        it 'returns 0 when the line does not contain the quote character' do
          expect(SmarterCSV.count_quote_chars('some text', '"')).to eq(0)
        end
      end

      # Additional cases
      context 'with additional cases' do
        it 'handles escape characters not followed by a quote character' do
          expect(SmarterCSV.count_quote_chars("abc\\ndef", '"')).to eq(0)
        end

        it 'correctly processes consecutive escape characters' do
          expect(SmarterCSV.count_quote_chars("a\\\\\"bc\"", '"')).to eq(2)
        end
      end
    end

    context 'with fixture files' do
      subject(:data) { SmarterCSV.process(file, options) }

      context 'when it is a strangely delimited file' do
        let(:file) { "#{fixture_path}/escaped_quote_char.csv" }

        it 'loads the csv file without issues' do
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

      context 'when it is a strangely delimited file' do
        let(:file) { "#{fixture_path}/escaped_quote_char_2.csv" }
        let(:options) do
          { quote_char: "!" }
        end

        it 'loads the csv file without issues' do
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

      context 'when it is a strangely delimited file' do
        let(:file) { "#{fixture_path}/escaped_quote_char_3.csv" }

        it 'loads the csv file without issues' do
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

      context 'when it is a strangely delimited file' do
        let(:file) { "#{fixture_path}/escaped_quote_char_4.csv" }
        let(:options) do
          { quote_char: "'" }
        end

        it 'loads the csv file without issues' do
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
end
