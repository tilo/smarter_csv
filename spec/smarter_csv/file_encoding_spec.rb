# frozen_string_literal: true

RSpec.describe SmarterCSV do
  describe 'encoding warning message' do
    let(:file_content) { "some,content\nwith,lines" }

    context 'with force_utf8 option and non-UTF-8 file encoding' do
      let(:file_io) { StringIO.new(file_content.encode(Encoding::ISO_8859_1)) }
      let(:options) { { force_utf8: true } }

      before do
        allow(file_io).to receive(:external_encoding).and_return(Encoding::ISO_8859_1)
      end

      it 'prints a warning about UTF-8 processing' do
        expect { described_class.process(file_io, options) }.to output(/WARNING: you are trying to process UTF-8 input/).to_stdout
      end
    end

    context 'with utf-8 file_encoding option and non-UTF-8 file encoding' do
      let(:file_io) { StringIO.new(file_content.encode(Encoding::ISO_8859_1)) }
      let(:options) { { file_encoding: 'utf-8' } }

      before do
        allow(file_io).to receive(:external_encoding).and_return(Encoding::ISO_8859_1)
      end

      it 'prints a warning about UTF-8 processing' do
        expect { described_class.process(file_io, options) }.to output(/WARNING: you are trying to process UTF-8 input/).to_stdout
      end
    end

    context 'with non-matching file_encoding option and non-UTF-8 file encoding' do
      let(:file_io) { StringIO.new(file_content.encode(Encoding::ISO_8859_1)) }
      let(:options) { { file_encoding: 'other-encoding' } }

      before do
        allow(file_io).to receive(:external_encoding).and_return(Encoding::ISO_8859_1)
      end

      it 'does not print a warning about UTF-8 processing' do
        expect { described_class.process(file_io, options) }.not_to output(/WARNING: you are trying to process UTF-8 input/).to_stdout
      end
    end

    context 'with force_utf8 option and UTF-8 file encoding' do
      let(:file_io) { StringIO.new(file_content.encode(Encoding::UTF_8)) }
      let(:options) { { force_utf8: true } }

      before do
        allow(file_io).to receive(:external_encoding).and_return(Encoding::UTF_8)
      end

      it 'does not print a warning about UTF-8 processing' do
        expect { described_class.process(file_io, options) }.not_to output(/WARNING: you are trying to process UTF-8 input/).to_stdout
      end
    end
  end
end
