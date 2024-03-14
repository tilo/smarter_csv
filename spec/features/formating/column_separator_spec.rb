# frozen_string_literal: true

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
          options.merge(user_provided_headers: %w[Name Age Job Department Project])
        )

        expect(data.first.keys.size).to eq 5
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
end
