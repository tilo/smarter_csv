# frozen_string_literal: true

require 'spec_helper'

describe 'options processing' do
  describe '#process_options' do
    it 'prints out given options in verbose mode' do
      options = {chunk_size: 10, verbose: true}
      allow($stdout).to receive(:puts)
      expect($stdout).to receive(:puts).with(/User provided options:/)
      expect($stdout).to receive(:puts).with(/Computed options:/)
      generated_options = SmarterCSV.process_options(options)
      expect(generated_options[:chunk_size]).to eq 10
    end

    it 'it has the correct default options, when no input is given' do
      generated_options = SmarterCSV.process_options({})
      expect(generated_options).to eq SmarterCSV::DEFAULT_OPTIONS
    end

    it 'lets the user clear out all default options' do
      options = {defaults: :none}
      generated_options = SmarterCSV.process_options(options)
      expect(generated_options).to eq options.merge(SmarterCSV::DEFAULT_OPTIONS)
    end

    it 'corrects :invalid_byte_sequence if nil is given' do
      generated_options = SmarterCSV.process_options(invalid_byte_sequence: nil)
      expect(generated_options[:invalid_byte_sequence]).to eq ''
    end
  end

  describe '#validate_options!' do
    it 'raises an exception for row_sep' do
      expect do
        invalid_options = {
          row_sep: nil,
        }
        SmarterCSV.process_options(invalid_options)
      end.to raise_exception(SmarterCSV::ValidationError, '["invalid row_sep"]')
    end

    it 'raises an exception for col_sep' do
      expect do
        invalid_options = {
          col_sep: nil,
        }
        SmarterCSV.process_options(invalid_options)
      end.to raise_exception(SmarterCSV::ValidationError, '["invalid col_sep"]')
    end

    it 'raises an exception for quote_char' do
      expect do
        invalid_options = {
          quote_char: nil,
        }
        SmarterCSV.process_options(invalid_options)
      end.to raise_exception(SmarterCSV::ValidationError, '["invalid quote_char"]')
    end
  end
end
