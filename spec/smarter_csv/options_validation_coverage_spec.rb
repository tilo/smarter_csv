# frozen_string_literal: true

# Additional coverage for options.rb:
# - required_headers deprecation path
# - quote_escaping validation
# - user_provided_headers auto-setting headers_in_file

describe 'options validation coverage' do
  let(:instance) { SmarterCSV::Reader.new('something', options) }
  let(:options) { {} }

  describe 'required_headers deprecation' do
    it 'converts required_headers to required_keys with a deprecation warning' do
      expect do
        generated_options = instance.process_options(required_headers: [:name, :email])
        expect(generated_options[:required_keys]).to eq [:name, :email]
        expect(generated_options[:required_headers]).to be_nil
      end.to output(/DEPRECATION WARNING.*required_keys/).to_stderr
    end

    it 'does not overwrite existing required_keys when required_headers is also given' do
      expect do
        generated_options = instance.process_options(required_headers: [:old], required_keys: [:new])
        # required_keys was already set, so it should NOT be overwritten
        expect(generated_options[:required_keys]).to eq [:new]
      end.to output(/DEPRECATION WARNING/).to_stderr
    end
  end

  describe 'quote_escaping validation' do
    it 'accepts :double_quotes' do
      expect do
        instance.process_options(quote_escaping: :double_quotes)
      end.not_to raise_error
    end

    it 'accepts :backslash' do
      expect do
        instance.process_options(quote_escaping: :backslash)
      end.not_to raise_error
    end

    it 'accepts :auto' do
      expect do
        instance.process_options(quote_escaping: :auto)
      end.not_to raise_error
    end

    it 'raises ValidationError for invalid quote_escaping value' do
      expect do
        instance.process_options(quote_escaping: :invalid)
      end.to raise_error(SmarterCSV::ValidationError, /invalid quote_escaping/)
    end

    it 'raises ValidationError for string quote_escaping' do
      expect do
        instance.process_options(quote_escaping: 'double_quotes')
      end.to raise_error(SmarterCSV::ValidationError, /invalid quote_escaping/)
    end
  end

  describe 'user_provided_headers auto-sets headers_in_file' do
    it 'sets headers_in_file to false when user_provided_headers given without explicit headers_in_file' do
      expect do
        generated_options = instance.process_options(user_provided_headers: [:a, :b])
        expect(generated_options[:headers_in_file]).to eq false
      end.to output(/WARNING.*headers_in_file/).to_stderr
    end

    it 'does not override explicit headers_in_file when user_provided_headers given' do
      generated_options = instance.process_options(user_provided_headers: [:a, :b], headers_in_file: true)
      expect(generated_options[:headers_in_file]).to eq true
    end
  end

  describe 'option_valid?' do
    it 'accepts :auto as a valid symbol' do
      expect do
        instance.process_options(row_sep: :auto)
      end.not_to raise_error
    end

    it 'rejects non-auto symbols' do
      expect do
        instance.process_options(col_sep: :tab)
      end.to raise_error(SmarterCSV::ValidationError)
    end

    it 'rejects numeric values' do
      expect do
        instance.process_options(quote_char: 1)
      end.to raise_error(SmarterCSV::ValidationError)
    end
  end
end
