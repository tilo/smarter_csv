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

  def read(n = nil)              = @io.read(n)
  def gets(sep = $/, limit = nil) = limit ? @io.gets(sep, limit) : @io.gets(sep)
  def readline(sep = $/)         = @io.readline(sep)
  def each_char(&block)    = @io.each_char(&block)
  def eof?                 = @io.eof?
  def external_encoding    = @encoding
  def close                = nil
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
end
