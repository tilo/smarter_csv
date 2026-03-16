# frozen_string_literal: true

require 'stringio'

fixture_path = 'spec/fixtures'

describe 'can handle col_sep' do
  it 'has default of comma as col_sep' do
    data = SmarterCSV.process("#{fixture_path}/separator_comma.csv") # no options
    expect(data.first.keys.size).to eq 5
    expect(data.size).to eq 3
  end

  describe 'with explicitly given col_sep' do
    it 'loads file with comma separator' do
      options = {col_sep: ','}
      data = SmarterCSV.process("#{fixture_path}/separator_comma.csv", options)
      expect(data.first.keys.size).to eq 5
      expect(data.size).to eq 3
    end

    it 'loads file with tab separator' do
      options = {col_sep: "\t"}
      data = SmarterCSV.process("#{fixture_path}/separator_tab.csv", options)
      expect(data.first.keys.size).to eq 5
      expect(data.size).to eq 3
    end

    it 'loads file with semi-colon separator' do
      options = {col_sep: ';'}
      data = SmarterCSV.process("#{fixture_path}/separator_semi.csv", options)
      expect(data.first.keys.size).to eq 5
      expect(data.size).to eq 3
    end

    it 'loads file with colon separator' do
      options = {col_sep: ':'}
      data = SmarterCSV.process("#{fixture_path}/separator_colon.csv", options)
      expect(data.first.keys.size).to eq 5
      expect(data.size).to eq 3
    end

    it 'loads file with pipe separator' do
      options = {col_sep: '|'}
      data = SmarterCSV.process("#{fixture_path}/separator_pipe.csv", options)
      expect(data.first.keys.size).to eq 5
      expect(data.size).to eq 3
    end
  end

  describe 'auto-detection of separator' do
    context 'when file has headers' do
      let(:options) { { col_sep: :auto, headers_in_file: true } }

      it 'auto-detects comma separator and loads data' do
        data = SmarterCSV.process("#{fixture_path}/separator_comma.csv", options)
        expect(data.first.keys.size).to eq 5
        expect(data.size).to eq 3
      end

      it 'auto-detects tab separator and loads data' do
        data = SmarterCSV.process("#{fixture_path}/separator_tab.csv", options)
        expect(data.first.keys.size).to eq 5
        expect(data.size).to eq 3
      end

      it 'auto-detects semi-colon separator and loads data' do
        data = SmarterCSV.process("#{fixture_path}/separator_semi.csv", options)
        expect(data.first.keys.size).to eq 5
        expect(data.size).to eq 3
      end

      it 'auto-detects colon separator and loads data' do
        data = SmarterCSV.process("#{fixture_path}/separator_colon.csv", options)
        expect(data.first.keys.size).to eq 5
        expect(data.size).to eq 3
      end

      it 'auto-detects pipe separator and loads data' do
        data = SmarterCSV.process("#{fixture_path}/separator_pipe.csv", options)

        expect(data.first.keys.size).to eq 5
        expect(data.size).to eq 3
      end

      it 'does not auto-detect other separators' do
        expect do
          SmarterCSV.process("#{fixture_path}/binary.csv", options)
        end.to raise_exception SmarterCSV::NoColSepDetected
      end

      it 'does not detect separators that are between quotes' do
        data = SmarterCSV.process("#{fixture_path}/separator_chars_between_quotes.csv", options)

        expect(data.first.keys.size).to eq 5
        expect(data.first[:"first,_last"]).to eq "John, Doe"
        expect(data.size).to eq 3
      end

      context 'when auto is given as a string' do
        let(:options) do
          {
            col_sep: 'auto',
            headers_in_file: true
          }
        end

        it 'also works' do
          data = SmarterCSV.process("#{fixture_path}/separator_pipe.csv", options)
          expect(data.first.keys.size).to eq 5
          expect(data.size).to eq 3
        end
      end
    end

    context 'when file has not headers' do
      let(:options) do
        {
          col_sep: :auto,
          headers_in_file: false,
          user_provided_headers: %w[Year Make Model Length]
        }
      end

      it 'auto-detects comma separator and loads data' do
        data = SmarterCSV.process("#{fixture_path}/separator_comma_no_headers.csv", options)
        expect(data.first.keys.size).to eq 4
        expect(data.size).to eq 3
      end

      it 'auto-detects tab separator and loads data' do
        data = SmarterCSV.process("#{fixture_path}/separator_tab_no_headers.csv", options)
        expect(data.first.keys.size).to eq 4
        expect(data.size).to eq 3
      end

      it 'auto-detects semi-colon separator and loads data' do
        data = SmarterCSV.process("#{fixture_path}/separator_semi_no_headers.csv", options)
        expect(data.first.keys.size).to eq 4
        expect(data.size).to eq 3
      end

      it 'auto-detects colon separator and loads data' do
        data = SmarterCSV.process("#{fixture_path}/separator_colon_no_headers.csv", options)
        expect(data.first.keys.size).to eq 4
        expect(data.size).to eq 3
      end

      it 'auto-detects pipe separator and loads data' do
        data = SmarterCSV.process("#{fixture_path}/separator_pipe_no_headers.csv", options)
        expect(data.first.keys.size).to eq 4
        expect(data.size).to eq 3
      end

      it 'does not auto-detect other separators' do
        expect do
          SmarterCSV.process("#{fixture_path}/binary_no_headers.csv", options)
        end.to raise_exception SmarterCSV::NoColSepDetected
      end

      it 'does not detect separators that are between quotes' do
        data = SmarterCSV.process(
          "#{fixture_path}/separator_chars_between_quotes_no_headers.csv",
          options.merge(headers_in_file: false, user_provided_headers: %w[Name Age Job Department Project])
        )

        expect(data.first.keys.size).to eq 5
        expect(data.first["Name"]).to eq "John, Doe"
        expect(data.size).to eq 3
      end

      context 'when auto is given as a string' do
        let(:options) do
          {
            col_sep: 'auto',
            headers_in_file: false,
            user_provided_headers: %w[Year Make Model Length]
          }
        end

        it 'also works' do
          data = SmarterCSV.process("#{fixture_path}/separator_pipe_no_headers.csv", options)
          expect(data.first.keys.size).to eq 4
          expect(data.size).to eq 3
        end
      end

      context 'when contents include a delimiter character with a count major than the number of columns' do
        let(:options) do
          {
            col_sep: :auto,
            headers_in_file: false,
            user_provided_headers: %w[Date1 Date2], # user provides strings
          }
        end

        it 'will fail to guess the separator' do
          data = SmarterCSV.process("#{fixture_path}/separator_comma_no_headers_will_fail.csv", options)
          expect(data.first['Date1']).to eq '2022-10-04 16' # Instead of 2022-10-04 16:00:47 UTC
          expect(data.first['Date2']).to eq 0 # Instead of 2022-10-04 16:00:47 UTC
        end
      end
    end
  end

  # -----------------------------------------------------------------------
  # Multi-char col_sep — C and Ruby paths must agree
  #
  # Multi-char separators always take the slow (character-by-character) path
  # in both C and Ruby — memchr fast path requires col_sep_len == 1.
  # Test both acceleration settings to ensure parity.
  # -----------------------------------------------------------------------
  describe 'with multi-char col_sep' do
    [true, false].each do |acceleration|
      context "acceleration: #{acceleration}" do
        it 'parses basic fields with a two-char separator' do
          csv = StringIO.new("name::age::city\nAlice::30::NYC\nBob::25::LA\n")
          data = SmarterCSV.process(csv, col_sep: '::', acceleration: acceleration)
          expect(data.size).to eq 2
          expect(data[0][:name]).to eq 'Alice'
          expect(data[0][:age]).to eq 30
          expect(data[0][:city]).to eq 'NYC'
          expect(data[1][:name]).to eq 'Bob'
          expect(data[1][:city]).to eq 'LA'
        end

        it 'handles a quoted field containing the multi-char separator' do
          csv = StringIO.new("first::second\naaa::\"hel::lo\"\n")
          data = SmarterCSV.process(csv, col_sep: '::', acceleration: acceleration)
          expect(data.size).to eq 1
          expect(data[0][:first]).to eq 'aaa'
          expect(data[0][:second]).to eq 'hel::lo'
        end

        it 'strips whitespace around fields with multi-char separator' do
          csv = StringIO.new("a::b::c\n hello :: world :: ! \n")
          data = SmarterCSV.process(csv, col_sep: '::', acceleration: acceleration,
                                         convert_values_to_numeric: false)
          expect(data.size).to eq 1
          expect(data[0][:a]).to eq 'hello'
          expect(data[0][:b]).to eq 'world'
          expect(data[0][:c]).to eq '!'
        end
      end
    end
  end

  # -----------------------------------------------------------------------
  # Multi-char col_sep combined with other options (Gaps 4, 5, 6)
  #
  # These tests verify that the slow path (always taken for multi-char sep)
  # correctly interacts with quote_escaping, remove_zero_values, and
  # remove_empty_values — options that are exercised independently elsewhere
  # but not yet tested in combination with multi-char col_sep.
  # -----------------------------------------------------------------------
  describe 'multi-char col_sep combined with other options' do
    [true, false].each do |acceleration|
      context "acceleration: #{acceleration}" do

        # Gap 4: multi-char col_sep + quote_escaping: :backslash
        context 'quote_escaping: :backslash' do
          it 'treats backslash-quote as escaped, keeping the quoted field open' do
            # CSV content: col_a::col_b  /  "X::Y\"ok"::Z
            # The \" inside the quoted field is an escaped quote (field stays open).
            # The :: inside the quoted field is part of the value (not a separator).
            csv = StringIO.new("col_a::col_b\n\"X::Y\\\"ok\"::Z\n")
            data = SmarterCSV.process(csv, col_sep: '::', acceleration: acceleration,
                                           quote_escaping: :backslash)
            expect(data.size).to eq 1
            expect(data[0][:col_a]).to eq "X::Y\\\"ok"
            expect(data[0][:col_b]).to eq 'Z'
          end

          it 'raises MalformedCSV when backslash escapes the closing quote (odd backslash count)' do
            # "abc\"::next — the \" escapes the closing quote, so the field is never closed
            csv = StringIO.new("col_a::col_b\n\"abc\\\"::next\n")
            expect do
              SmarterCSV.process(csv, col_sep: '::', acceleration: acceleration,
                                      quote_escaping: :backslash)
            end.to raise_error(SmarterCSV::MalformedCSV)
          end

          it 'double backslash closes the field normally' do
            # "abc\\"::def — even backslash count: field closes at the quote
            csv = StringIO.new("col_a::col_b\n\"abc\\\\\"::def\n")
            data = SmarterCSV.process(csv, col_sep: '::', acceleration: acceleration,
                                           quote_escaping: :backslash)
            expect(data.size).to eq 1
            expect(data[0][:col_a]).to eq "abc\\\\"
            expect(data[0][:col_b]).to eq 'def'
          end
        end

        # Gap 5: multi-char col_sep + remove_zero_values
        context 'remove_zero_values: true' do
          it 'removes integer zero fields' do
            csv = StringIO.new("name::count::score\nAlice::0::3.14\nBob::5::0\n")
            data = SmarterCSV.process(csv, col_sep: '::', acceleration: acceleration,
                                           remove_zero_values: true, remove_empty_values: true)
            expect(data.size).to eq 2
            alice = data[0]
            expect(alice[:name]).to eq 'Alice'
            expect(alice).not_to have_key(:count)  # 0 removed
            expect(alice[:score]).to eq 3.14
            bob = data[1]
            expect(bob[:count]).to eq 5
            expect(bob).not_to have_key(:score)    # 0 removed
          end

          it 'removes float zero fields' do
            csv = StringIO.new("name::price::qty\nWidget::0.0::3\nGadget::9.99::0.00\n")
            data = SmarterCSV.process(csv, col_sep: '::', acceleration: acceleration,
                                           remove_zero_values: true, remove_empty_values: true)
            expect(data.size).to eq 2
            expect(data[0]).not_to have_key(:price)  # 0.0 removed
            expect(data[0][:qty]).to eq 3
            expect(data[1][:price]).to eq 9.99
            expect(data[1]).not_to have_key(:qty)    # 0.00 removed
          end
        end

        # Gap 6: multi-char col_sep + remove_empty_values
        context 'remove_empty_values: true' do
          it 'removes blank fields' do
            csv = StringIO.new("name::notes::value\nAlice::::42\nBob::   ::99\n")
            data = SmarterCSV.process(csv, col_sep: '::', acceleration: acceleration,
                                           remove_empty_values: true, convert_values_to_numeric: false)
            expect(data.size).to eq 2
            data.each { |row| expect(row.keys).not_to include(:notes) }
            expect(data[0][:name]).to eq 'Alice'
            expect(data[0][:value]).to eq '42'
            expect(data[1][:name]).to eq 'Bob'
            expect(data[1][:value]).to eq '99'
          end

          it 'keeps empty fields when remove_empty_values is false' do
            csv = StringIO.new("name::notes::value\nAlice::::42\n")
            data = SmarterCSV.process(csv, col_sep: '::', acceleration: acceleration,
                                           remove_empty_values: false, convert_values_to_numeric: false)
            expect(data.size).to eq 1
            expect(data[0]).to have_key(:notes)
            expect(data[0][:notes]).to eq ''
          end
        end

      end

      # Multi-char col_sep + multiline fields (quoted field spanning rows)
      context 'multiline quoted fields' do
        it 'stitches a quoted field spanning two rows' do
          csv = StringIO.new("name::notes::value\nAlice::\"line one\nline two\"::42\n")
          data = SmarterCSV.process(csv, col_sep: '::', acceleration: acceleration)
          expect(data.size).to eq 1
          expect(data[0][:name]).to eq 'Alice'
          expect(data[0][:notes]).to eq "line one\nline two"
          expect(data[0][:value]).to eq 42
        end

        it 'stitches multiple multiline rows independently' do
          csv = StringIO.new("a::b\n\"one\ntwo\"::X\n\"three\nfour\"::Y\n")
          data = SmarterCSV.process(csv, col_sep: '::', acceleration: acceleration)
          expect(data.size).to eq 2
          expect(data[0][:a]).to eq "one\ntwo"
          expect(data[0][:b]).to eq 'X'
          expect(data[1][:a]).to eq "three\nfour"
          expect(data[1][:b]).to eq 'Y'
        end
      end

    end
  end
end
