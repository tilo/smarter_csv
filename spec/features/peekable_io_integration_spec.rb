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

  def read(n = nil)        = @io.read(n)
  def gets(sep = $/)       = @io.gets(sep)
  def readline(sep = $/)   = @io.readline(sep)
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
      result = SmarterCSV.process(io, col_sep: ',', row_sep: :auto)
      expect(result).to eq([{ name: 'Alice', age: '30' }, { name: 'Bob', age: '25' }])
    ensure
      io.close unless io.closed?
    end

    it 'auto-detects col_sep on a pipe' do
      io = pipe_for("name;age\nAlice;30\nBob;25\n")
      result = SmarterCSV.process(io, col_sep: :auto, row_sep: "\n")
      expect(result).to eq([{ name: 'Alice', age: '30' }, { name: 'Bob', age: '25' }])
    ensure
      io.close unless io.closed?
    end

    it 'auto-detects both col_sep and row_sep on a pipe' do
      io = pipe_for("name\tage\r\nAlice\t30\r\nBob\t25\r\n")
      result = SmarterCSV.process(io, col_sep: :auto, row_sep: :auto)
      expect(result).to eq([{ name: 'Alice', age: '30' }, { name: 'Bob', age: '25' }])
    ensure
      io.close unless io.closed?
    end

    it 'processes a pipe correctly when no auto-detection is needed' do
      io = pipe_for("name,age\nAlice,30\n")
      result = SmarterCSV.process(io, col_sep: ',', row_sep: "\n")
      expect(result).to eq([{ name: 'Alice', age: '30' }])
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
      result = SmarterCSV.process(io, col_sep: ',', row_sep: :auto)
      expect(result).to eq([{ name: 'Alice', age: '30' }, { name: 'Bob', age: '25' }])
    end

    it 'auto-detects col_sep' do
      io = NonSeekableIO.new("name|age\nAlice|30\nBob|25\n")
      result = SmarterCSV.process(io, col_sep: :auto, row_sep: "\n")
      expect(result).to eq([{ name: 'Alice', age: '30' }, { name: 'Bob', age: '25' }])
    end

    it 'auto-detects both separators' do
      io = NonSeekableIO.new("name\tage\r\nAlice\t30\r\nBob\t25\r\n")
      result = SmarterCSV.process(io, col_sep: :auto, row_sep: :auto)
      expect(result).to eq([{ name: 'Alice', age: '30' }, { name: 'Bob', age: '25' }])
    end

    it 'handles non-UTF-8 encoding (ISO-8859-1)' do
      io = NonSeekableIO.new("name,city\nAlice,München\n", encoding: Encoding::ISO_8859_1)
      result = SmarterCSV.process(io, col_sep: ',', row_sep: "\n", file_encoding: 'iso-8859-1')
      expect(result.first[:name]).to eq('Alice')
    end
  end

  # ---------------------------------------------------------------------------
  # Regression: file-based sources must still work unchanged
  # ---------------------------------------------------------------------------
  describe 'file source regression' do
    let(:fixture_path) { File.join(File.dirname(__FILE__), '..', 'fixtures', 'basic.csv') }

    it 'still processes a regular file with auto-detection' do
      result = SmarterCSV.process(fixture_path, col_sep: :auto, row_sep: :auto)
      expect(result).not_to be_empty
    end

    it 'still processes a StringIO with auto-detection' do
      io = StringIO.new("a,b\n1,2\n3,4\n")
      result = SmarterCSV.process(io, col_sep: :auto, row_sep: :auto)
      expect(result).to eq([{ a: '1', b: '2' }, { a: '3', b: '4' }])
    end
  end
end
