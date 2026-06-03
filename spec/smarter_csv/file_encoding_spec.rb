# frozen_string_literal: true

require 'tempfile'

RSpec.describe SmarterCSV do
  # ---------------------------------------------------------------------------
  # enforce_utf8_encoding — unit-level tests
  #
  # This private method is called on every line when @enforce_utf8 = true, which
  # happens when file_encoding !~ /utf-8/i or force_utf8: true.
  #
  # The key invariant: non-ASCII bytes must be TRANSCODED to UTF-8, not dropped.
  # force_encoding('utf-8') is a lie — it relabels bytes without converting them,
  # turning valid ISO-8859-1/Windows-1252 codepoints into invalid UTF-8 sequences
  # that encode() then replaces with ''.  The fix is to use line.encoding as the
  # source in encode() whenever the line carries a known non-UTF-8 encoding.
  # ---------------------------------------------------------------------------
  describe '#enforce_utf8_encoding (via send)' do
    let(:reader) do
      r = SmarterCSV::Reader.new(StringIO.new("a\n1\n"), {})
      r.send(:process) rescue nil
      r
    end

    def transcode(reader, str)
      reader.send(:enforce_utf8_encoding, str, { invalid_byte_sequence: '' })
    end

    context 'ISO-8859-1 input (file_encoding: iso-8859-1)' do
      # \xe9 = é, \xfc = ü in ISO-8859-1
      let(:line) { "M\xFCnchen, caf\xe9".b.force_encoding('ISO-8859-1') }

      it 'transcodes non-ASCII characters to UTF-8 (not drops them)' do
        result = transcode(reader, line)
        expect(result).to eq('München, café')
      end

      it 'returns a valid UTF-8 string' do
        result = transcode(reader, line)
        expect(result.encoding).to eq(Encoding::UTF_8)
        expect(result.valid_encoding?).to be true
      end
    end

    context 'Windows-1252 input (file_encoding: windows-1252)' do
      # \x80 = € (euro sign) in Windows-1252; not a valid ISO-8859-1 or UTF-8 byte
      let(:line) { "price: \x80100".b.force_encoding('Windows-1252') }

      it 'transcodes Windows-1252 bytes including the euro sign' do
        result = transcode(reader, line)
        expect(result).to eq('price: €100')
      end

      it 'returns a valid UTF-8 string' do
        result = transcode(reader, line)
        expect(result.encoding).to eq(Encoding::UTF_8)
        expect(result.valid_encoding?).to be true
      end
    end

    context 'UTF-8 input with invalid bytes (force_utf8: true on a UTF-8 file)' do
      # \xc3\xbc = ü in UTF-8 (valid); \xff is invalid in UTF-8
      let(:valid_utf8)   { "M\xC3\xBCnchen".dup.force_encoding('UTF-8') }
      let(:invalid_utf8) { "bad\xFF byte".dup.force_encoding('UTF-8') }

      it 'leaves valid UTF-8 unchanged' do
        result = transcode(reader, valid_utf8)
        expect(result).to eq('München')
        expect(result.encoding).to eq(Encoding::UTF_8)
      end

      it 'replaces invalid UTF-8 sequences with the replacement string' do
        result = transcode(reader, invalid_utf8)
        expect(result).to eq('bad byte')
        expect(result.encoding).to eq(Encoding::UTF_8)
      end
    end

    context 'ASCII-8BIT input (file_encoding: binary — Encoding::BINARY is an alias for Encoding::ASCII_8BIT)' do
      # .b returns a string tagged as Encoding::ASCII_8BIT.
      # Encoding::BINARY is just another name for the same constant — same object identity.
      let(:line) { "M\xC3\xBCnchen".b }

      it 'input is tagged as ASCII_8BIT (the canonical name)' do
        expect(line.encoding).to eq(Encoding::ASCII_8BIT)
      end

      it 'Encoding::BINARY is the same object as Encoding::ASCII_8BIT' do
        expect(Encoding::BINARY).to equal(Encoding::ASCII_8BIT)
      end

      it 'reinterprets ASCII_8BIT bytes as UTF-8 and returns a valid UTF-8 string' do
        result = transcode(reader, line)
        expect(result).to eq('München')
        expect(result.encoding).to eq(Encoding::UTF_8)
        expect(result.valid_encoding?).to be true
      end
    end

    context 'Shift-JIS input (file_encoding: shift_jis)' do
      # encode() produces a new (unfrozen) string in Shift-JIS
      let(:line) { '東京, 大阪'.encode('Shift_JIS') }

      it 'transcodes Shift-JIS characters to UTF-8' do
        expect(transcode(reader, line)).to eq('東京, 大阪')
      end

      it 'returns a valid UTF-8 string' do
        result = transcode(reader, line)
        expect(result.encoding).to eq(Encoding::UTF_8)
        expect(result.valid_encoding?).to be true
      end
    end

    context 'EUC-JP input (file_encoding: euc-jp)' do
      let(:line) { '東京, 大阪'.encode('EUC-JP') }

      it 'transcodes EUC-JP characters to UTF-8' do
        expect(transcode(reader, line)).to eq('東京, 大阪')
      end

      it 'returns a valid UTF-8 string' do
        result = transcode(reader, line)
        expect(result.encoding).to eq(Encoding::UTF_8)
        expect(result.valid_encoding?).to be true
      end
    end

    context 'UTF-16LE input (file_encoding: utf-16le)' do
      let(:line) { 'München'.encode('UTF-16LE') }

      it 'transcodes UTF-16LE characters to UTF-8' do
        expect(transcode(reader, line)).to eq('München')
      end

      it 'returns a valid UTF-8 string' do
        result = transcode(reader, line)
        expect(result.encoding).to eq(Encoding::UTF_8)
        expect(result.valid_encoding?).to be true
      end
    end

    context 'custom invalid_byte_sequence replacement character' do
      let(:line_utf8)    { "bad\xFF byte".dup.force_encoding('UTF-8') }
      let(:line_iso)     { "M\xFCnchen".b.force_encoding('ISO-8859-1') }

      it 'uses the specified replacement for invalid bytes in UTF-8 input' do
        result = reader.send(:enforce_utf8_encoding, line_utf8, { invalid_byte_sequence: '?' })
        expect(result).to eq('bad? byte')
      end

      it 'does not insert replacement for valid transcoded bytes (ISO-8859-1 → UTF-8)' do
        result = reader.send(:enforce_utf8_encoding, line_iso, { invalid_byte_sequence: '?' })
        expect(result).to eq('München') # ü transcodes cleanly — no replacement needed
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Transcoding pair path — file_encoding: 'ext:int'
  #
  # When file_encoding contains a colon (e.g. 'iso-8859-1:UTF-8'), Ruby opens
  # the file with a transcoding pair.  @enforce_utf8 = false (string matches
  # /utf-8/i), so enforce_utf8_encoding is NEVER called.  Instead,
  # PeekableIO#maybe_transcode performs the ext→int conversion when replaying
  # buffered bytes.
  #
  # spec/fixtures/problematic.csv is an ISO-8859-1 file with French accented
  # characters in the header: opération, libellé, référence.
  # ---------------------------------------------------------------------------
  describe 'transcoding pair: file_encoding ext:int (maybe_transcode path)' do
    let(:fixture) { 'spec/fixtures/problematic.csv' }
    let(:accented_keys) { %w[date_opération libellé référence] }

    context 'iso-8859-1:UTF-8' do
      let(:opts) { { file_encoding: 'iso-8859-1:UTF-8', col_sep: ';', verbose: :quiet } }

      it 'transcodes ISO-8859-1 headers to correctly spelled UTF-8 keys' do
        result = SmarterCSV.process(fixture, **opts, strings_as_keys: true)
        expect(result.first.keys).to include(*accented_keys)
      end

      it 'returns UTF-8 strings' do
        result = SmarterCSV.process(fixture, **opts, strings_as_keys: true)
        result.first.each_key do |k|
          expect(k.encoding).to eq(Encoding::UTF_8)
          expect(k.valid_encoding?).to be true
        end
      end

      it 'parses all data rows' do
        expect(SmarterCSV.process(fixture, **opts).length).to eq(7)
      end
    end

    context 'windows-1252:UTF-8' do
      # Build an in-memory Windows-1252 CSV with the euro sign (\x80).
      # Use a TranscodedIO so PeekableIO sees the correct ext/int encoding pair.
      let(:transcoded_io_class) do
        Class.new do
          def initialize(raw_bytes, ext, int)
            @io  = StringIO.new(raw_bytes.b)
            @ext = Encoding.find(ext)
            @int = Encoding.find(int)
          end

          def read(n = nil)
            @io.read(n)
          end

          def gets(sep = $/, limit = nil)
            limit ? @io.gets(sep, limit) : @io.gets(sep)
          end

          def readline(sep = $/)
            @io.readline(sep)
          end

          def each_char(&block)
            @io.each_char(&block)
          end

          def eof?
            @io.eof?
          end

          def close
            nil
          end

          def external_encoding
            @ext
          end

          def internal_encoding
            @int
          end
        end
      end

      # \x80 = € in Windows-1252
      let(:csv_w1252) { "product,price\nWidget,\x80100\n".b }

      it 'transcodes Windows-1252 bytes (including euro sign) to UTF-8' do
        io = transcoded_io_class.new(csv_w1252, 'Windows-1252', 'UTF-8')
        result = SmarterCSV.process(io, col_sep: :auto, row_sep: :auto, verbose: :quiet)
        expect(result.first[:price]).to eq('€100')
        expect(result.first[:price].encoding).to eq(Encoding::UTF_8)
      end
    end

    context 'windows-1252:UTF-8 (via Tempfile — same path as the iso-8859-1 test above)' do
      # \x80 = € in Windows-1252
      let(:csv_w1252_bytes) { "product,price\nWidget,\x80100\n".b }

      it 'transcodes Windows-1252 bytes (including euro sign) to UTF-8' do
        Tempfile.open(['w1252', '.csv']) do |f|
          f.binmode
          f.write(csv_w1252_bytes)
          f.close
          result = SmarterCSV.process(f.path, file_encoding: 'windows-1252:UTF-8', col_sep: :auto, row_sep: :auto, verbose: :quiet)
          expect(result.first[:price]).to eq('€100')
          expect(result.first[:price].encoding).to eq(Encoding::UTF_8)
        end
      end
    end

    context 'windows-1252:UTF-8 (via a Pathname path — file_encoding must apply when opening a Pathname)' do
      # \x80 = € in Windows-1252. SmarterCSV opens the Pathname itself with the requested
      # file_encoding (reader.rb: File.open(input, "r:#{file_encoding}")), so the euro sign
      # must transcode the same as when a String path is given.
      let(:csv_w1252_bytes) { "product,price\nWidget,\x80100\n".b }

      it 'transcodes Windows-1252 bytes (including euro sign) to UTF-8' do
        require 'pathname'
        Tempfile.open(['w1252', '.csv']) do |f|
          f.binmode
          f.write(csv_w1252_bytes)
          f.close
          result = SmarterCSV.process(Pathname.new(f.path), file_encoding: 'windows-1252:UTF-8', col_sep: :auto, row_sep: :auto, verbose: :quiet)
          expect(result.first[:price]).to eq('€100')
          expect(result.first[:price].encoding).to eq(Encoding::UTF_8)
        end
      end
    end
  end

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
        expect { described_class.process(file_path, options) }.to output(/WARNING: you are trying to process UTF-8 input/).to_stderr
      end
    end

    context 'with utf-8 file_encoding option and non-UTF-8 file encoding' do
      let(:options) { { file_encoding: 'utf-8' } }

      before do
        allow(file_double).to receive(:external_encoding).and_return(Encoding.find('ISO-8859-1'))
      end

      it 'prints a warning about UTF-8 processing' do
        expect { described_class.process(file_path, options) }.to output(/WARNING: you are trying to process UTF-8 input/).to_stderr
      end
    end

    context 'with non-matching file_encoding option and non-UTF-8 file encoding' do
      let(:options) { { file_encoding: 'other-encoding' } }

      before do
        allow(file_double).to receive(:external_encoding).and_return(Encoding.find('ISO-8859-1'))
      end

      it 'does not print a warning about UTF-8 processing' do
        expect { described_class.process(file_path, options) }.not_to output(/WARNING: you are trying to process UTF-8 input/).to_stderr
      end
    end

    context 'with force_utf8 option and UTF-8 file encoding' do
      let(:options) { { force_utf8: true } }

      before do
        allow(file_double).to receive(:external_encoding).and_return(Encoding.find('UTF-8'))
      end

      it 'does not print a warning about UTF-8 processing' do
        expect { described_class.process(file_path, options) }.not_to output(/WARNING: you are trying to process UTF-8 input/).to_stderr
      end
    end
  end
end
