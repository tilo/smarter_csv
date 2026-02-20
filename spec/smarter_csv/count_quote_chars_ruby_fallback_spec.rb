# frozen_string_literal: true

# Tests for the Ruby fallback paths of count_quote_chars and count_quote_chars_auto.
# On MRI Ruby, @has_acceleration is always true (C extension loaded), so the Ruby
# fallback code is never exercised. These tests stub @has_acceleration to false
# to ensure the Ruby implementation is covered.

describe 'count_quote_chars Ruby fallback' do
  let(:reader) { SmarterCSV::Reader.new('something', {}) }

  before do
    # Force Ruby fallback by disabling acceleration detection
    reader.instance_variable_set(:@has_acceleration, false)
  end

  describe '#count_quote_chars with quote_escaping: :double_quotes' do
    it 'counts all quote characters in a line' do
      expect(reader.count_quote_chars('"No" "Escaping"', '"', ',', :double_quotes)).to eq 4
    end

    it 'counts quotes without treating backslash as escape' do
      # "D\"Angelos" has 3 quote chars — backslash is literal in :double_quotes mode
      expect(reader.count_quote_chars('"D\"Angelos"', '"', ',', :double_quotes)).to eq 3
    end

    it 'handles custom quote char' do
      expect(reader.count_quote_chars("\!D\\\!Angelos\!", "\!", ",", :double_quotes)).to eq 3
    end

    it 'returns 0 for nil line' do
      expect(reader.count_quote_chars(nil, '"', ',')).to eq 0
    end

    it 'returns 0 for nil quote_char' do
      expect(reader.count_quote_chars('hello', nil, ',')).to eq 0
    end

    it 'returns 0 for empty quote_char' do
      expect(reader.count_quote_chars('hello', '', ',')).to eq 0
    end

    it 'returns 0 when no quotes are present' do
      expect(reader.count_quote_chars('hello,world', '"', ',', :double_quotes)).to eq 0
    end
  end

  describe '#count_quote_chars with quote_escaping: :backslash' do
    it 'handles escaped characters and regular characters' do
      expect(reader.count_quote_chars('"No" "Escaping"', '"', ',', :backslash)).to eq 4
      expect(reader.count_quote_chars('"D\"Angelos"', '"', ',', :backslash)).to eq 2
      expect(reader.count_quote_chars("\!D\\\!Angelos\!", "\!", ",", :backslash)).to eq 2
    end

    it 'does not count backslash-escaped quotes' do
      # \" is escaped, should not be counted
      expect(reader.count_quote_chars('\"hello\"', '"', ',', :backslash)).to eq 0
    end

    it 'counts quote after double backslash (backslash escapes backslash, not quote)' do
      # \\" -> backslash escapes backslash, then quote is unescaped
      expect(reader.count_quote_chars('\\\\"', '"', ',', :backslash)).to eq 1
    end
  end

  describe '#count_quote_chars_auto' do
    it 'returns [escaped_count, rfc_count] for dual counting' do
      # No backslashes — both counts are the same
      escaped, rfc = reader.count_quote_chars_auto('"No" "Escaping"', '"', ',')
      expect(escaped).to eq 4
      expect(rfc).to eq 4
    end

    it 'skips backslash-escaped quotes in escaped_count but not rfc_count' do
      # "D\"Angelos" — backslash-aware count skips the escaped quote
      escaped, rfc = reader.count_quote_chars_auto('"D\"Angelos"', '"', ',')
      expect(escaped).to eq 2
      expect(rfc).to eq 3
    end

    it 'handles complex backslash sequences' do
      # "\",Y — trace:
      # " -> rfc=1, escaped=1
      # \ -> escaped=true
      # " -> rfc=2, escaped: yes -> skip
      # , -> escaped=false
      # Y -> escaped=false
      escaped, rfc = reader.count_quote_chars_auto('"\",Y', '"', ',')
      expect(escaped).to eq 1
      expect(rfc).to eq 2
    end

    it 'returns [0, 0] for nil line' do
      expect(reader.count_quote_chars_auto(nil, '"', ',')).to eq [0, 0]
    end

    it 'returns [0, 0] for nil quote_char' do
      expect(reader.count_quote_chars_auto('hello', nil, ',')).to eq [0, 0]
    end

    it 'returns [0, 0] for empty quote_char' do
      expect(reader.count_quote_chars_auto('hello', '', ',')).to eq [0, 0]
    end

    it 'handles double backslash before quote (backslash escapes backslash)' do
      # \\" -> \\ escapes to literal backslash, " is unescaped
      escaped, rfc = reader.count_quote_chars_auto('\\\\"', '"', ',')
      expect(escaped).to eq 1
      expect(rfc).to eq 1
    end
  end
end
