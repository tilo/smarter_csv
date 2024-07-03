# frozen_string_literal: true

fixture_path = 'spec/fixtures'

#
# required_headers
#
describe 'test exceptions for invalid headers' do
  it 'does not raise an error if required_keys not provided' do
    data = SmarterCSV.process("#{fixture_path}/user_import.csv")
    expect(data.size).to eq 2
  end

  context "required_keys: if keys are missing after mapping" do
    it 'does not raise an error if no required headers are given' do
      options = {required_keys: nil} # order does not matter
      data = SmarterCSV.process("#{fixture_path}/user_import.csv", options)
      expect(data.size).to eq 2
    end

    it 'does not raise an error if required headers are empty' do
      options = {required_keys: []} # order does not matter
      data = SmarterCSV.process("#{fixture_path}/user_import.csv", options)
      expect(data.size).to eq 2
    end

    it 'does not raise an error if the required headers are present' do
      options = {required_keys: %i[lastname email firstname manager_email]} # order does not matter
      data = SmarterCSV.process("#{fixture_path}/user_import.csv", options)
      expect(data.size).to eq 2
    end

    it 'raises an error if a required header is missing' do
      expect do
        options = {required_keys: %i[lastname email employee_id firstname manager_email]} # order does not matter
        SmarterCSV.process("#{fixture_path}/user_import.csv", options)
      end.to raise_exception(
        SmarterCSV::MissingKeys, "ERROR: missing attributes: employee_id. Check `reader.headers` for original headers."
      )
    end

    it 'raises error on missing mapped headers' do
      options = { required_keys: [:email], key_mapping: {email: :something_was_mapped} }
      expect do
        SmarterCSV.process("#{fixture_path}/user_import.csv", options)
      end.to raise_exception(
        SmarterCSV::MissingKeys, /ERROR: missing attributes: email/ # it was mapped, and is now missing
      )
    end
  end

  # TO BE FIXED:
  #
  # this raises:  SmarterCSV::MissingKeys: RROR: missing attributes: middle_name
  # but instead, the printed WARNING message for missing_keys should raise KeyMappingError
  # See: Issue 139 https://github.com/tilo/smarter_csv/issues/139
  #
  context 'mapping_keys: exception for missing keys / header names' do
    subject(:process_file) { SmarterCSV.process("#{fixture_path}/user_import.csv", options) }

    context 'when one key_mapping key is missing' do
      let(:options) do
        {
          required_keys: [:middle_name],
          key_mapping: { missing_key: :middle_name},
        }
      end

      it 'raises exception that header for the key mapping is missing in file' do
        expect(SmarterCSV).not_to receive(:puts).with a_string_matching(/WARNING.*missing_key/)
        # we do not expect version 1.8 behavior:
        expect{ process_file }.not_to raise_exception(
          SmarterCSV::MissingKeys, "ERROR: missing attributes: middle_name"
        )
        # we expect version 1.9 behavior:
        expect{ process_file }.to raise_exception(
          SmarterCSV::KeyMappingError, "ERROR: can not map headers: missing_key"
        )
      end
    end

    context "when multiple keys are missing" do
      let(:options) do
        { key_mapping: { missing_key: :middle_name, other_missing_key: :other } }
      end

      it 'raises exception that headers for the key mapping are missing in the file' do
        expect(SmarterCSV).not_to receive(:puts).with a_string_matching(/WARNING.*missing_key/)
        expect{ process_file }.to raise_exception(
          SmarterCSV::KeyMappingError, "ERROR: can not map headers: missing_key, other_missing_key"
        )
      end

      it "does not raise any exception when :silence_missing_keys is true" do
        options[:silence_missing_keys] = true
        expect(SmarterCSV).not_to receive(:puts).with a_string_matching(/WARNING.*missing_key/)
        expect{ process_file }.not_to raise_exception
      end
    end

    context "when slience_missing_keys is used" do
      let(:options) do
        {
          required_keys: [:middle_name],
          key_mapping: { missing_key: :middle_name, other_optional_key: :other },
        }
      end

      context "when invalid key_mapping is given" do
        it "does not raise a KeyMappingError exception when :silence_missing_keys is true" do
          options[:silence_missing_keys] = true
          expect(SmarterCSV).not_to receive(:puts).with a_string_matching(/WARNING.*missing_key/)
          expect{ process_file }.not_to raise_exception SmarterCSV::KeyMappingError
          # still raises an error because :middle_name is required
          expect{ process_file }.to raise_exception(
            SmarterCSV::MissingKeys, /ERROR: missing attributes: middle_name/
          )
        end
      end

      it "does not raise an exception when :silence_missing_keys is an array containing the missing key" do
        options[:silence_missing_keys] = [:missing_key, :other_optional_key]
        expect(SmarterCSV).not_to receive(:puts).with a_string_matching(/WARNING.*missing_key/)
        expect{ process_file }.not_to raise_exception(
          SmarterCSV::KeyMappingError, "ERROR: can not map headers: missing_key"
        )
        # still raises an error because :middle_name is required
        expect{ process_file }.to raise_exception(
          SmarterCSV::MissingKeys, /ERROR: missing attributes: middle_name/
        )
      end

      it "raises an exception when :silence_missing_keys is an array but does not contain the missing key" do
        options[:silence_missing_keys] = [:other_optional_key]
        expect(SmarterCSV).not_to receive(:puts).with a_string_matching(/WARNING.*missing_key/)
        # raises KeyMappingError because :missing_key is required:
        expect{ process_file }.to raise_exception(
          SmarterCSV::KeyMappingError, "ERROR: can not map headers: missing_key"
        )
      end
    end
  end
end
