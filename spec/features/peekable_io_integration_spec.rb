# frozen_string_literal: true

require 'spec_helper'
require 'stringio'
require 'zlib'

# Simulates STDIN / pipes / any IO that intentionally has no rewind or seek.
class NonSeekableIO
  def initialize(str, encoding: Encoding::UTF_8)
    @io = StringIO.new(str.encode(encoding))
    @encoding = encoding
  end

  def read(n = nil)             ; @io.read(n)                                   ; end
  def gets(sep = $/, limit = nil); limit ? @io.gets(sep, limit) : @io.gets(sep); end
  def readline(sep = $/)        ; @io.readline(sep)                             ; end
  def each_char(&block)         ; @io.each_char(&block)                         ; end
  def eof?                      ; @io.eof?                                      ; end
  def external_encoding         ; @encoding                                     ; end
  def close                     ; nil                                           ; end
  # Intentionally does NOT implement rewind or seek
end

RSpec.describe 'PeekableIO integration — non-seekable sources' do
  # ---------------------------------------------------------------------------
  # IO.pipe
  # ---------------------------------------------------------------------------
  describe 'IO.pipe source' do
    def pipe_for(content)
      reader, writer = IO.pipe
      writer.write(content)
      writer.close
      reader
    end

    it 'auto-detects row_sep on a pipe' do
      io = pipe_for("name,age\nAlice,30\nBob,25\n")
      result = SmarterCSV.process(io, col_sep: ',', row_sep: :auto, )
      expect(result).to eq([{ name: 'Alice', age: 30 }, { name: 'Bob', age: 25 }])
    ensure
      io.close unless io.closed?
    end

    it 'auto-detects col_sep on a pipe' do
      io = pipe_for("name;age\nAlice;30\nBob;25\n")
      result = SmarterCSV.process(io, col_sep: :auto, row_sep: "\n", )
      expect(result).to eq([{ name: 'Alice', age: 30 }, { name: 'Bob', age: 25 }])
    ensure
      io.close unless io.closed?
    end

    it 'auto-detects both col_sep and row_sep on a pipe' do
      io = pipe_for("name\tage\r\nAlice\t30\r\nBob\t25\r\n")
      result = SmarterCSV.process(io, col_sep: :auto, row_sep: :auto, )
      expect(result).to eq([{ name: 'Alice', age: 30 }, { name: 'Bob', age: 25 }])
    ensure
      io.close unless io.closed?
    end

    it 'processes a pipe correctly when no auto-detection is needed' do
      io = pipe_for("name,age\nAlice,30\n")
      result = SmarterCSV.process(io, col_sep: ',', row_sep: "\n", )
      expect(result).to eq([{ name: 'Alice', age: 30 }])
    ensure
      io.close unless io.closed?
    end
  end

  # ---------------------------------------------------------------------------
  # NonSeekableIO (STDIN-like)
  # ---------------------------------------------------------------------------
  describe 'NonSeekableIO source (STDIN-like, no rewind)' do
    it 'auto-detects row_sep' do
      io = NonSeekableIO.new("name,age\nAlice,30\nBob,25\n")
      result = SmarterCSV.process(io, col_sep: ',', row_sep: :auto, )
      expect(result).to eq([{ name: 'Alice', age: 30 }, { name: 'Bob', age: 25 }])
    end

    it 'auto-detects col_sep' do
      io = NonSeekableIO.new("name|age\nAlice|30\nBob|25\n")
      result = SmarterCSV.process(io, col_sep: :auto, row_sep: "\n", )
      expect(result).to eq([{ name: 'Alice', age: 30 }, { name: 'Bob', age: 25 }])
    end

    it 'auto-detects both separators' do
      io = NonSeekableIO.new("name\tage\r\nAlice\t30\r\nBob\t25\r\n")
      result = SmarterCSV.process(io, col_sep: :auto, row_sep: :auto, )
      expect(result).to eq([{ name: 'Alice', age: 30 }, { name: 'Bob', age: 25 }])
    end

    it 'handles non-UTF-8 encoding (ISO-8859-1)' do
      io = NonSeekableIO.new("name,city\nAlice,München\n", encoding: Encoding::ISO_8859_1)
      result = SmarterCSV.process(io, col_sep: ',', row_sep: "\n", file_encoding: 'iso-8859-1')
      expect(result.first[:name]).to eq('Alice')
    end
  end

  # ---------------------------------------------------------------------------
  # File path (string) — seekable, auto-opened by smarter_csv
  # ---------------------------------------------------------------------------
  describe 'file path source' do
    let(:fixture_path) { File.join(File.dirname(__FILE__), '..', 'fixtures', 'basic.csv') }

    it 'processes a file path with auto-detection' do
      result = SmarterCSV.process(fixture_path, col_sep: :auto, row_sep: :auto)
      expect(result).not_to be_empty
    end

    it 'processes a file path with explicit separators (no peek)' do
      result = SmarterCSV.process(fixture_path, col_sep: ',', row_sep: "\n")
      expect(result).not_to be_empty
    end
  end

  # ---------------------------------------------------------------------------
  # Open File object — seekable, caller-opened file handle
  # ---------------------------------------------------------------------------
  describe 'open File object source' do
    let(:fixture_path) { File.join(File.dirname(__FILE__), '..', 'fixtures', 'basic.csv') }

    it 'processes an open File with auto-detection' do
      File.open(fixture_path, 'r:utf-8') do |fh|
        result = SmarterCSV.process(fh, col_sep: :auto, row_sep: :auto)
        expect(result).not_to be_empty
      end
    end

    it 'processes an open File with explicit separators (no peek)' do
      File.open(fixture_path, 'r:utf-8') do |fh|
        result = SmarterCSV.process(fh, col_sep: ',', row_sep: "\n")
        expect(result).not_to be_empty
      end
    end
  end

  # ---------------------------------------------------------------------------
  # StringIO — seekable, in-memory
  # ---------------------------------------------------------------------------
  describe 'StringIO source' do
    it 'processes StringIO with auto-detection' do
      io = StringIO.new("a,b\n1,2\n3,4\n")
      result = SmarterCSV.process(io, col_sep: :auto, row_sep: :auto)
      expect(result).to eq([{ a: 1, b: 2 }, { a: 3, b: 4 }])
    end

    it 'processes StringIO with explicit separators (no peek)' do
      io = StringIO.new("a,b\n1,2\n3,4\n")
      result = SmarterCSV.process(io, col_sep: ',', row_sep: "\n")
      expect(result).to eq([{ a: 1, b: 2 }, { a: 3, b: 4 }])
    end
  end

  # ---------------------------------------------------------------------------
  # NonSeekableIO — explicit separators (no peek path)
  # ---------------------------------------------------------------------------
  describe 'NonSeekableIO source — explicit separators' do
    it 'processes without auto-detection (no peek needed)' do
      io = NonSeekableIO.new("name,age\nAlice,30\nBob,25\n")
      result = SmarterCSV.process(io, col_sep: ',', row_sep: "\n")
      expect(result).to eq([{ name: 'Alice', age: 30 }, { name: 'Bob', age: 25 }])
    end
  end

  # ---------------------------------------------------------------------------
  # Zlib::GzipReader — non-seekable compressed stream
  # ---------------------------------------------------------------------------
  describe 'Zlib::GzipReader source' do
    def gzip_io_for(content)
      buf = StringIO.new(''.b)
      gz = Zlib::GzipWriter.new(buf)
      gz.write(content)
      gz.finish
      Zlib::GzipReader.new(StringIO.new(buf.string))
    end

    it 'auto-detects both separators on a gzip stream' do
      gz = gzip_io_for("name,age\nAlice,30\nBob,25\n")
      result = SmarterCSV.process(gz, col_sep: :auto, row_sep: :auto)
      expect(result).to eq([{ name: 'Alice', age: 30 }, { name: 'Bob', age: 25 }])
    end

    it 'processes a gzip stream with explicit separators (no peek)' do
      gz = gzip_io_for("name,age\nAlice,30\nBob,25\n")
      result = SmarterCSV.process(gz, col_sep: ',', row_sep: "\n")
      expect(result).to eq([{ name: 'Alice', age: 30 }, { name: 'Bob', age: 25 }])
    end
  end

  # ---------------------------------------------------------------------------
  # BOM files with explicit separators — exercises remove_bom in file_io.rb
  # (no peek is called, so PeekableIO passes through to @io and remove_bom
  #  handles the BOM on the first line)
  # ---------------------------------------------------------------------------
  describe 'BOM file with explicit separators (no peek path)' do
    let(:fixtures) { File.join(File.dirname(__FILE__), '..', 'fixtures') }

    it 'strips UTF-8 BOM (efbbbf) when separators are explicit' do
      result = SmarterCSV.process("#{fixtures}/bom_test_efbbbf.csv", col_sep: ',', row_sep: "\r\n")
      expect(result.first[:some_id]).to eq(42_766_805)
    end

    it 'strips UTF-16LE BOM (fffe) when separators are explicit' do
      result = SmarterCSV.process("#{fixtures}/bom_test_fffe.csv", col_sep: ',', row_sep: "\r\n")
      expect(result.first[:some_id]).to eq(42_766_805)
    end

    it 'strips UTF-16BE BOM (feff) when separators are explicit' do
      result = SmarterCSV.process("#{fixtures}/bom_test_feff.csv", col_sep: ',', row_sep: "\r\n")
      expect(result.first[:some_id]).to eq(42_766_805)
    end
  end

  # ---------------------------------------------------------------------------
  # Encoding and transcoding
  # spec/fixtures/problematic.csv is ISO-8859-1 with French accented characters
  # in the header row: opération (\xe9), libellé (\xe9), référence (\xe9).
  #
  # Two distinct code paths in reader.rb:
  #
  # A. Transcoding pair ("iso-8859-1:UTF-8"):
  #    @enforce_utf8 = false (matches /utf-8/i) → enforce_utf8_encoding is NEVER
  #    called.  PeekableIO's maybe_transcode performs the ext→int conversion when
  #    replaying buffered bytes from the peek buffer.
  #
  # B. Single encoding ("iso-8859-1"):
  #    @enforce_utf8 = true → enforce_utf8_encoding is called on every line.
  #    enforce_utf8_encoding uses line.encoding as the source in encode(), so
  #    ISO-8859-1 bytes are properly transcoded to UTF-8.
  #    maybe_transcode is a no-op (internal_encoding is nil for single encodings).
  # ---------------------------------------------------------------------------
  describe 'encoding and transcoding' do
    let(:iso_fixture) { File.join(File.dirname(__FILE__), '..', 'fixtures', 'problematic.csv') }
    # Expected UTF-8 header keys after downcasing and space→underscore normalisation
    let(:accented_keys) { %w[date_opération libellé référence] }

    # Path A: transcoding pair — maybe_transcode in PeekableIO does the work.
    # verbose: :quiet suppresses the false-positive "not opened with b:utf-8"
    # warning that reader.rb emits when file_encoding contains "UTF-8" but the
    # underlying handle's external_encoding is non-UTF-8 (expected for transcoding pairs).
    context 'transcoding pair: file_encoding iso-8859-1:UTF-8 (maybe_transcode path)' do
      let(:opts) { { file_encoding: 'iso-8859-1:UTF-8', col_sep: ';', verbose: :quiet } }

      it 'returns correctly transcoded UTF-8 header keys' do
        result = SmarterCSV.process(iso_fixture, **opts, strings_as_keys: true)
        expect(result.first.keys).to include(*accented_keys)
      end

      it 'returns header key strings encoded as UTF-8' do
        result = SmarterCSV.process(iso_fixture, **opts, strings_as_keys: true)
        result.first.each_key do |k|
          expect(k.encoding).to eq(Encoding::UTF_8), "key #{k.inspect} has encoding #{k.encoding}"
          expect(k.valid_encoding?).to be true
        end
      end

      it 'parses all 7 data rows' do
        result = SmarterCSV.process(iso_fixture, **opts)
        expect(result.length).to eq(7)
      end

      it 'auto-detects separators (peek + rewind + maybe_transcode on buffered replay)' do
        result = SmarterCSV.process(iso_fixture,
          **opts, col_sep: :auto, row_sep: :auto, strings_as_keys: true)
        expect(result.first.keys).to include(*accented_keys)
        expect(result.length).to eq(7)
      end
    end

    # Path B: single encoding — enforce_utf8_encoding transcodes using the line's
    # declared encoding (ISO-8859-1) as the source, producing correct UTF-8 output.
    context 'single encoding: file_encoding iso-8859-1 (enforce_utf8_encoding path)' do
      it 'does not raise and parses all 7 data rows' do
        result = SmarterCSV.process(iso_fixture, file_encoding: 'iso-8859-1', col_sep: ';')
        expect(result.length).to eq(7)
      end

      it 'returns correctly transcoded UTF-8 header keys' do
        result = SmarterCSV.process(iso_fixture,
          file_encoding: 'iso-8859-1',
          col_sep: ';',
          strings_as_keys: true)
        expect(result.first.keys).to include(*accented_keys)
        result.first.each_key do |k|
          expect(k.encoding).to eq(Encoding::UTF_8), "key #{k.inspect} has encoding #{k.encoding}"
        end
      end
    end

    # Non-seekable source with a transcoding pair (ext=ISO-8859-1, int=UTF-8).
    # When auto-detection is requested, peek fills the buffer from the raw IO,
    # then maybe_transcode converts ISO-8859-1 → UTF-8 on every gets call from
    # the buffer after rewind — even though the source is non-seekable.
    context 'non-seekable transcoding stream (ext=ISO-8859-1, int=UTF-8)' do
      # IO class that reports both external_encoding and internal_encoding but
      # does NOT support rewind — simulates a pipe or STDIN with encoding metadata.
      # maybe_transcode uses these to perform ext→int conversion on buffered reads.
      let(:transcoded_io_class) do
        Class.new do
          def initialize(raw_bytes, external, internal)
            @io  = StringIO.new(raw_bytes.b)
            @ext = Encoding.find(external)
            @int = Encoding.find(internal)
          end
          def read(n = nil)             ; @io.read(n)                                   ; end
          def gets(sep = $/, limit = nil); limit ? @io.gets(sep, limit) : @io.gets(sep); end
          def readline(sep = $/)        ; @io.readline(sep)                             ; end
          def each_char(&block)         ; @io.each_char(&block)                         ; end
          def eof?                      ; @io.eof?                                      ; end
          def close                     ; nil                                           ; end
          def external_encoding         ; @ext                                          ; end
          def internal_encoding         ; @int                                          ; end
          # Intentionally no rewind or seek
        end
      end

      # \xfc = ü in ISO-8859-1; \xe9 = é in ISO-8859-1
      let(:csv_iso) { "name,city,note\nAlice,M\xFCnchen,caf\xe9\n".b }

      it 'transcodes ISO-8859-1 bytes to UTF-8 via maybe_transcode after peek + rewind' do
        io = transcoded_io_class.new(csv_iso, 'ISO-8859-1', 'UTF-8')
        result = SmarterCSV.process(io, col_sep: :auto, row_sep: :auto, verbose: :quiet)
        expect(result.first[:city]).to eq('München')
        expect(result.first[:city].encoding).to eq(Encoding::UTF_8)
        expect(result.first[:note]).to eq('café')
      end
    end
  end
end
