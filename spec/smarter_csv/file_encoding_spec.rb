# frozen_string_literal: true

require 'spec_helper'

RSpec.describe SmarterCSV do
  describe 'encoding warning message' do
    let(:file_path) { 'path/to/csvfile.csv' }
    let(:file_content) { "some,content\nwith,lines" }
    let(:file_double) { StringIO.new(file_content) }

    before do
      allow(File).to receive(:open).with(file_path, anything).and_return(file_double)
    end

    context 'with force_utf8 option and non-UTF-8 file encoding' do
      let(:options) { { force_utf8: true } }

      before do
        allow(file_double).to receive(:external_encoding).and_return(Encoding.find('ISO-8859-1'))
      end

      it 'prints a warning about UTF-8 processing' do
        expect { described_class.process(file_path, options) }.to output(/WARNING: you are trying to process UTF-8 input/).to_stdout
      end
    end

    context 'with utf-8 file_encoding option and non-UTF-8 file encoding' do
      let(:options) { { file_encoding: 'utf-8' } }

      before do
        allow(file_double).to receive(:external_encoding).and_return(Encoding.find('ISO-8859-1'))
      end

      it 'prints a warning about UTF-8 processing' do
        expect { described_class.process(file_path, options) }.to output(/WARNING: you are trying to process UTF-8 input/).to_stdout
      end
    end

    context 'with non-matching file_encoding option and non-UTF-8 file encoding' do
      let(:options) { { file_encoding: 'other-encoding' } }

      before do
        allow(file_double).to receive(:external_encoding).and_return(Encoding.find('ISO-8859-1'))
      end

      it 'does not print a warning about UTF-8 processing' do
        expect { described_class.process(file_path, options) }.not_to output(/WARNING: you are trying to process UTF-8 input/).to_stdout
      end
    end

    context 'with force_utf8 option and UTF-8 file encoding' do
      let(:options) { { force_utf8: true } }

      before do
        allow(file_double).to receive(:external_encoding).and_return(Encoding.find('UTF-8'))
      end

      it 'does not print a warning about UTF-8 processing' do
        expect { described_class.process(file_path, options) }.not_to output(/WARNING: you are trying to process UTF-8 input/).to_stdout
      end
    end
  end
end

