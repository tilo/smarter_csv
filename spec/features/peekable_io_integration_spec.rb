# frozen_string_literal: true

require 'spec_helper'
require 'stringio'
require 'zlib'
require 'tempfile'

# Simulates STDIN / pipes / any IO that intentionally has no rewind or seek.
class NonSeekableIO
  def initialize(str, encoding: Encoding::UTF_8)
    @io = StringIO.new(str.encode(encoding))
    @encoding = encoding
  end

  def read(num_bytes = nil)
    @io.read(num_bytes)
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

  def external_encoding
    @encoding
  end

  def close
    nil
  end
  # Intentionally does NOT implement rewind or seek
end

# Non-seekable IO with raw pre-encoded bytes and explicit encoding metadata.
# Used for testing encoding paths on non-seekable sources (pipes, STDIN with encoding info).
# Unlike NonSeekableIO, accepts bytes already in the target encoding rather than calling encode().
class EncodedBytesIO
  def initialize(raw_bytes, external_enc, internal_enc = nil)
    @io  = StringIO.new(raw_bytes.b)
    @ext = Encoding.find(external_enc)
    @int = internal_enc ? Encoding.find(internal_enc) : nil
  end

  def read(num_bytes = nil)
    @io.read(num_bytes)
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
  # Intentionally does NOT implement rewind or seek
end

# Sizes chosen to stress-test distinct code paths in PeekableIO:
#   3    — forces \r\n to straddle every other boundary; maximally exercises straddle detection
#   19   — prime close to one data row (~13-19 bytes); hits different byte offsets than 3
#   128  — ~1/3 of the 400-byte matrix content; several extend_buffer! calls + short frozen phase
#   512  — larger than matrix content; frozen phase starts early; stress-tests large-file delegation
#   4096 — roughly 1/10 of the 44KB large-file content; exercises both detection and long frozen phase
INTERESTING_BUFFER_SIZES = [3, 19, 128, 512, 4096].freeze

RSpec.describe 'PeekableIO integration — non-seekable sources' do
  # Shared generator — used by both the in-memory and Tempfile-based test sections.
  def large_csv_content(rows: 2_000, col_sep: ',', row_sep: "\n")
    header = "id#{col_sep}name#{col_sep}value#{row_sep}"
    data   = (1..rows).map { |i| "#{i}#{col_sep}item_#{i}#{col_sep}#{i * 100}#{row_sep}" }.join
    header + data
  end

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
      expect(result).to eq([{ name: 'Alice', age: 30 }, { name: 'Bob', age: 25 }])
    ensure
      io.close unless io.closed?
    end

    it 'auto-detects col_sep on a pipe' do
      io = pipe_for("name;age\nAlice;30\nBob;25\n")
      result = SmarterCSV.process(io, col_sep: :auto, row_sep: "\n")
      expect(result).to eq([{ name: 'Alice', age: 30 }, { name: 'Bob', age: 25 }])
    ensure
      io.close unless io.closed?
    end

    it 'auto-detects both col_sep and row_sep on a pipe' do
      io = pipe_for("name\tage\r\nAlice\t30\r\nBob\t25\r\n")
      result = SmarterCSV.process(io, col_sep: :auto, row_sep: :auto)
      expect(result).to eq([{ name: 'Alice', age: 30 }, { name: 'Bob', age: 25 }])
    ensure
      io.close unless io.closed?
    end

    it 'processes a pipe correctly when no auto-detection is needed' do
      io = pipe_for("name,age\nAlice,30\n")
      result = SmarterCSV.process(io, col_sep: ',', row_sep: "\n")
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
      result = SmarterCSV.process(io, col_sep: ',', row_sep: :auto)
      expect(result).to eq([{ name: 'Alice', age: 30 }, { name: 'Bob', age: 25 }])
    end

    it 'auto-detects col_sep' do
      io = NonSeekableIO.new("name|age\nAlice|30\nBob|25\n")
      result = SmarterCSV.process(io, col_sep: :auto, row_sep: "\n")
      expect(result).to eq([{ name: 'Alice', age: 30 }, { name: 'Bob', age: 25 }])
    end

    it 'auto-detects both separators' do
      io = NonSeekableIO.new("name\tage\r\nAlice\t30\r\nBob\t25\r\n")
      result = SmarterCSV.process(io, col_sep: :auto, row_sep: :auto)
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
  # Large file — multiple 16KB buffer blocks
  #
  # 2000 rows × ~22 bytes ≈ 44KB — exercises:
  #   a) detection within the initial 16KB peek buffer
  #   b) frozen-phase delegation to @io for rows beyond the buffer
  #   c) first and last rows correct (last is read from @io, not the buffer)
  # ---------------------------------------------------------------------------
  describe 'large file spanning multiple 16KB buffer blocks' do
    it 'parses all rows correctly with auto-detection (StringIO)' do
      io = StringIO.new(large_csv_content)
      result = SmarterCSV.process(io, col_sep: :auto, row_sep: :auto)
      expect(result.length).to eq(2_000)
      expect(result.first).to eq({ id: 1, name: 'item_1', value: 100 })
      expect(result.last).to  eq({ id: 2_000, name: 'item_2000', value: 200_000 })
    end

    it 'parses all rows correctly with auto-detection (NonSeekableIO pipe-like)' do
      io = NonSeekableIO.new(large_csv_content)
      result = SmarterCSV.process(io, col_sep: :auto, row_sep: :auto)
      expect(result.length).to eq(2_000)
      expect(result.first).to eq({ id: 1, name: 'item_1', value: 100 })
      expect(result.last).to  eq({ id: 2_000, name: 'item_2000', value: 200_000 })
    end

    it 'parses all rows correctly with auto-detection (Zlib stream)' do
      buf = StringIO.new(''.b)
      Zlib::GzipWriter.new(buf).tap do |gz|
        gz.write(large_csv_content)
        gz.finish
      end
      gz = Zlib::GzipReader.new(StringIO.new(buf.string))
      result = SmarterCSV.process(gz, col_sep: :auto, row_sep: :auto)
      expect(result.length).to eq(2_000)
      expect(result.first).to eq({ id: 1, name: 'item_1', value: 100 })
      expect(result.last).to  eq({ id: 2_000, name: 'item_2000', value: 200_000 })
    end

    it 'parses all rows correctly with chunk_size on NonSeekableIO' do
      io = NonSeekableIO.new(large_csv_content)
      chunks = SmarterCSV.process(io, col_sep: :auto, row_sep: :auto, chunk_size: 100)
      expect(chunks.length).to eq(20) # 2000 rows / 100 per chunk
      expect(chunks.first.length).to eq(100)
      expect(chunks.first.first).to eq({ id: 1, name: 'item_1', value: 100 })
      expect(chunks.last.last).to   eq({ id: 2_000, name: 'item_2000', value: 200_000 })
    end
  end

  # ---------------------------------------------------------------------------
  # skip_lines with auto-detection
  #
  # Tests the new detection flow where comment lines are skipped BETWEEN
  # row_sep detection and col_sep detection so that col_sep sees data lines,
  # not comment lines.
  # ---------------------------------------------------------------------------
  describe 'skip_lines with auto-detection' do
    def csv_with_comments(skip: 2, col_sep: ',', row_sep: "\n")
      comments = (1..skip).map { |i| "# comment line #{i}#{row_sep}" }.join
      comments + "id#{col_sep}name#{col_sep}value#{row_sep}" \
                 "1#{col_sep}Alice#{col_sep}100#{row_sep}" \
                 "2#{col_sep}Bob#{col_sep}200#{row_sep}"
    end

    it 'auto-detects col_sep correctly when comment lines precede the header (StringIO)' do
      io = StringIO.new(csv_with_comments)
      result = SmarterCSV.process(io, col_sep: :auto, row_sep: :auto, skip_lines: 2)
      expect(result).to eq([{ id: 1, name: 'Alice', value: 100 }, { id: 2, name: 'Bob', value: 200 }])
    end

    it 'auto-detects col_sep correctly when comment lines precede the header (NonSeekableIO)' do
      io = NonSeekableIO.new(csv_with_comments)
      result = SmarterCSV.process(io, col_sep: :auto, row_sep: :auto, skip_lines: 2)
      expect(result).to eq([{ id: 1, name: 'Alice', value: 100 }, { id: 2, name: 'Bob', value: 200 }])
    end

    it 'works with tab-separated content after comment lines' do
      content = "# comment\n# another\nid\tname\tvalue\n1\tAlice\t100\n2\tBob\t200\n"
      io = NonSeekableIO.new(content)
      result = SmarterCSV.process(io, col_sep: :auto, row_sep: :auto, skip_lines: 2)
      expect(result).to eq([{ id: 1, name: 'Alice', value: 100 }, { id: 2, name: 'Bob', value: 200 }])
    end

    # col_sep is fixed, only row_sep is :auto — skip_lines fires in the detection
    # block before guess_column_separator, which is wasteful but must still produce
    # correct results.
    it 'produces correct results when col_sep is fixed and only row_sep is :auto' do
      content = "# comment 1\n# comment 2\nid,name,value\n1,Alice,100\n2,Bob,200\n"
      io = NonSeekableIO.new(content)
      result = SmarterCSV.process(io, col_sep: ',', row_sep: :auto, skip_lines: 2)
      expect(result).to eq([{ id: 1, name: 'Alice', value: 100 }, { id: 2, name: 'Bob', value: 200 }])
    end

    # row_sep is fixed, only col_sep is :auto — skip_lines must fire so that
    # guess_column_separator sees the header line, not a comment line.
    it 'produces correct results when row_sep is fixed and only col_sep is :auto' do
      content = "# comment 1\n# comment 2\nid,name,value\n1,Alice,100\n2,Bob,200\n"
      io = NonSeekableIO.new(content)
      result = SmarterCSV.process(io, col_sep: :auto, row_sep: "\n", skip_lines: 2)
      expect(result).to eq([{ id: 1, name: 'Alice', value: 100 }, { id: 2, name: 'Bob', value: 200 }])
    end
  end

  # ---------------------------------------------------------------------------
  # Empty input with auto-detection
  #
  # Verifies that the correct errors are raised rather than crashes or silent
  # wrong results. For all empty-input cases, EmptyFileError is the correct error:
  # auto-detection falls back gracefully (guess_line_ending → "\n",
  # guess_column_separator → ",") so process_headers always raises EmptyFileError.
  # ---------------------------------------------------------------------------
  describe 'empty input with auto-detection' do
    # For all empty-input cases, EmptyFileError is the semantically correct error.
    # Auto-detection falls back gracefully (guess_line_ending → "\n",
    # guess_column_separator → ",") so that process_headers — which reads the
    # first line and finds nil — is always the one that raises.
    it 'raises EmptyFileError for empty input when both separators are :auto' do
      io = NonSeekableIO.new('')
      expect { SmarterCSV.process(io, col_sep: :auto, row_sep: :auto) }
        .to raise_error(SmarterCSV::EmptyFileError)
    end

    it 'raises EmptyFileError for empty input when only row_sep is :auto' do
      io = NonSeekableIO.new('')
      expect { SmarterCSV.process(io, col_sep: ',', row_sep: :auto) }
        .to raise_error(SmarterCSV::EmptyFileError)
    end

    it 'raises EmptyFileError for empty input when only col_sep is :auto' do
      expect { SmarterCSV.process(StringIO.new(''), col_sep: :auto, row_sep: "\n") }
        .to raise_error(SmarterCSV::EmptyFileError)
    end

    it 'raises EmptyFileError for empty input when both separators are fixed' do
      expect { SmarterCSV.process(StringIO.new(''), col_sep: ',', row_sep: "\n") }
        .to raise_error(SmarterCSV::EmptyFileError)
    end
  end

  # ---------------------------------------------------------------------------
  # \r-only line endings (old Mac format)
  # ---------------------------------------------------------------------------
  describe '\r-only line endings' do
    it 'auto-detects \\r row separator on NonSeekableIO' do
      io = NonSeekableIO.new("name,age\rAlice,30\rBob,25\r")
      result = SmarterCSV.process(io, col_sep: :auto, row_sep: :auto)
      expect(result).to eq([{ name: 'Alice', age: 30 }, { name: 'Bob', age: 25 }])
    end

    it 'auto-detects \\r row separator on a pipe' do
      reader, writer = IO.pipe
      writer.write("name,age\rAlice,30\rBob,25\r")
      writer.close
      result = SmarterCSV.process(reader, col_sep: :auto, row_sep: :auto)
      expect(result).to eq([{ name: 'Alice', age: 30 }, { name: 'Bob', age: 25 }])
    ensure
      reader.close unless reader.closed?
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
  # Tempfile-based tests — real file IO (seekable, path-based, encoding metadata)
  # without committing large fixtures to the repo.
  #
  # Covers:
  #   - file path (String) as input — exercises File.open inside reader.rb
  #   - open File handle as input — caller-opened, reader must not close it
  #   - various separator combinations: \n, \r\n, tab col_sep, semicolon col_sep
  #   - skip_lines with a real file
  #   - large gzip file (non-seekable compressed stream, real Tempfile backing)
  # ---------------------------------------------------------------------------
  describe 'Tempfile-based generated fixtures' do
    def with_csv_tempfile(content, binary: false)
      t = Tempfile.new(['smarter_csv_test', '.csv'])
      t.binmode if binary
      t.write(content)
      t.flush
      yield t.path
    ensure
      t.close
      t.unlink
    end

    def with_gzip_tempfile(content)
      t = Tempfile.new(['smarter_csv_test', '.csv.gz'])
      t.close
      Zlib::GzipWriter.open(t.path) { |gz| gz.write(content) }
      yield t.path
    ensure
      t.unlink
    end

    let(:rows)         { 2_000 }
    let(:content_lf)   { large_csv_content(rows: rows, col_sep: ',',  row_sep: "\n")   }
    let(:content_crlf) { large_csv_content(rows: rows, col_sep: ',',  row_sep: "\r\n") }
    let(:content_tab)  { large_csv_content(rows: rows, col_sep: "\t", row_sep: "\n")   }
    let(:content_semi) { large_csv_content(rows: rows, col_sep: ';',  row_sep: "\r\n") }

    let(:first_row) { { id: 1,     name: 'item_1',    value: 100     } }
    let(:last_row)  { { id: 2_000, name: 'item_2000', value: 200_000 } }

    context 'file path (String) input' do
      it 'auto-detects , and \\n' do
        with_csv_tempfile(content_lf) do |path|
          result = SmarterCSV.process(path, col_sep: :auto, row_sep: :auto)
          expect(result.length).to eq(rows)
          expect(result.first).to eq(first_row)
          expect(result.last).to  eq(last_row)
        end
      end

      it 'auto-detects , and \\r\\n' do
        with_csv_tempfile(content_crlf) do |path|
          result = SmarterCSV.process(path, col_sep: :auto, row_sep: :auto)
          expect(result.length).to eq(rows)
          expect(result.first).to eq(first_row)
          expect(result.last).to  eq(last_row)
        end
      end

      it 'auto-detects tab and \\n' do
        with_csv_tempfile(content_tab) do |path|
          result = SmarterCSV.process(path, col_sep: :auto, row_sep: :auto)
          expect(result.length).to eq(rows)
          expect(result.first).to eq(first_row)
          expect(result.last).to  eq(last_row)
        end
      end

      it 'auto-detects ; and \\r\\n' do
        with_csv_tempfile(content_semi) do |path|
          result = SmarterCSV.process(path, col_sep: :auto, row_sep: :auto)
          expect(result.length).to eq(rows)
          expect(result.first).to eq(first_row)
          expect(result.last).to  eq(last_row)
        end
      end

      it 'auto-detects separators with skip_lines (comment lines before header)' do
        content = "# generated file\n# skip me too\n" + content_lf
        with_csv_tempfile(content) do |path|
          result = SmarterCSV.process(path, col_sep: :auto, row_sep: :auto, skip_lines: 2)
          expect(result.length).to eq(rows)
          expect(result.first).to eq(first_row)
          expect(result.last).to  eq(last_row)
        end
      end
    end

    context 'open File handle input' do
      it 'auto-detects , and \\n from an open File' do
        with_csv_tempfile(content_lf) do |path|
          File.open(path, 'r:utf-8') do |fh|
            result = SmarterCSV.process(fh, col_sep: :auto, row_sep: :auto)
            expect(result.length).to eq(rows)
            expect(result.first).to eq(first_row)
            expect(result.last).to  eq(last_row)
          end
        end
      end

      it 'auto-detects , and \\r\\n from an open File' do
        with_csv_tempfile(content_crlf) do |path|
          File.open(path, 'r:utf-8') do |fh|
            result = SmarterCSV.process(fh, col_sep: :auto, row_sep: :auto)
            expect(result.length).to eq(rows)
            expect(result.first).to eq(first_row)
            expect(result.last).to  eq(last_row)
          end
        end
      end
    end

    context 'gzip Tempfile (non-seekable compressed, large)' do
      it 'auto-detects , and \\n from a large gzip file' do
        with_gzip_tempfile(content_lf) do |path|
          result = SmarterCSV.process(Zlib::GzipReader.open(path), col_sep: :auto, row_sep: :auto)
          expect(result.length).to eq(rows)
          expect(result.first).to eq(first_row)
          expect(result.last).to  eq(last_row)
        end
      end

      it 'auto-detects ; and \\r\\n from a large gzip file' do
        with_gzip_tempfile(content_semi) do |path|
          result = SmarterCSV.process(Zlib::GzipReader.open(path), col_sep: :auto, row_sep: :auto)
          expect(result.length).to eq(rows)
          expect(result.first).to eq(first_row)
          expect(result.last).to  eq(last_row)
        end
      end
    end
  end

  # ---------------------------------------------------------------------------
  # BOM files with auto-detection — BOM is stripped in peek, then separators
  # are auto-detected from the clean content.
  # ---------------------------------------------------------------------------
  describe 'BOM file with auto-detection (peek path)' do
    let(:fixtures) { File.join(File.dirname(__FILE__), '..', 'fixtures') }

    it 'strips UTF-8 BOM and auto-detects separators' do
      result = SmarterCSV.process("#{fixtures}/bom_test_efbbbf.csv", col_sep: :auto, row_sep: :auto)
      expect(result.first[:some_id]).to eq(42_766_805)
    end

    it 'strips UTF-16LE BOM and auto-detects separators' do
      result = SmarterCSV.process("#{fixtures}/bom_test_fffe.csv", col_sep: :auto, row_sep: :auto)
      expect(result.first[:some_id]).to eq(42_766_805)
    end

    it 'strips UTF-16BE BOM and auto-detects separators' do
      result = SmarterCSV.process("#{fixtures}/bom_test_feff.csv", col_sep: :auto, row_sep: :auto)
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

          def read(num_bytes = nil)
            @io.read(num_bytes)
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

  # ---------------------------------------------------------------------------
  # Peek boundary lands inside a multi-byte UTF-8 codepoint
  #
  # Byte layout of the content below (UTF-8):
  #   0-7  : "key,val\n"  (header, 8 bytes)
  #   8-9  : "a,"         (2 bytes)
  #   10   : "M"          (1 byte)
  #   11   : 0xC3         ← first byte of ü  ← buffer ends HERE with buffer_size=12
  #   12   : 0xBC         ← second byte of ü
  #
  # auto_row_sep_chars: 6 → buffer_size: 12.
  # The initial peek reads exactly 12 bytes, stopping at 0xC3.
  # align_to_char_boundary must read one more byte (0xBC) to complete the codepoint.
  # Without that fix peek would store a truncated ü and maybe_transcode would
  # replace it with the Unicode replacement character.
  # ---------------------------------------------------------------------------
  describe 'buffer boundary inside a multi-byte UTF-8 codepoint (align_to_char_boundary)' do
    it 'peek landing mid-codepoint is corrected by align_to_char_boundary' do
      rows = (1..20).map { |i| "a,München_#{i}\n" }.join
      csv  = "key,val\n" + rows
      io   = NonSeekableIO.new(csv)
      result = SmarterCSV.process(io, col_sep: :auto, row_sep: :auto, auto_row_sep_chars: 6)
      expect(result.length).to eq(20)
      expect(result.first[:val]).to eq('München_1')
      expect(result.first[:val].encoding).to eq(Encoding::UTF_8)
      expect(result.last[:val]).to eq('München_20')
      expect(result.last[:val].encoding).to eq(Encoding::UTF_8)
    end
  end

  # ---------------------------------------------------------------------------
  # Deterministic \r\n separator straddling the frozen buffer/IO boundary
  #
  # "name,city\r\n" = 12 bytes. buffer_size: 10 → peek reads exactly "name,city\r"
  # (ends on 0x0D). @io starts with "\n...".
  # The straddle-detection branch in frozen-phase gets must read 1 byte ahead,
  # confirm the separator, and stitch the line correctly.
  # ---------------------------------------------------------------------------
  describe 'deterministic \\r\\n straddling the frozen buffer/IO boundary' do
    it '\\r at end of peek buffer, \\n as first @io byte' do
      raw = "name,city\r\nAlice,NYC\r\nBob,LA\r\n"
      io  = NonSeekableIO.new(raw)
      opts = SmarterCSV::Reader::Options::DEFAULT_OPTIONS.merge(row_sep: "\r\n", col_sep: ",")
      pio = SmarterCSV::PeekableIO.new(io, opts, buffer_size: 10)
      pio.peek           # fills buffer: "name,city\r" (10 bytes, ends on \r = 0x0D)
      pio.freeze_buffer! # freeze immediately — skip auto-detection
      pio.rewind_buffer  # replay from byte 0

      lines = []
      while (line = pio.gets("\r\n"))
        lines << line
      end

      expect(lines.length).to eq(3)
      expect(lines[0]).to eq("name,city\r\n")
      expect(lines[1]).to eq("Alice,NYC\r\n")
      expect(lines[2]).to eq("Bob,LA\r\n")
    end
  end

  # ---------------------------------------------------------------------------
  # Single data row wider than buffer_size
  #
  # Each row is ~210 bytes; buffer_size: 32 → each row spans 6+ extend_buffer!
  # calls in the non-frozen gets loop and then frozen-phase delegation reads the
  # same oversized rows from @io.
  # ---------------------------------------------------------------------------
  describe 'single data row wider than buffer_size' do
    it 'handles rows longer than buffer_size via multiple extend_buffer! calls' do
      wide_value = 'x' * 200
      rows = (1..10).map { |i| "item_#{i},#{wide_value}_#{i}\n" }.join
      csv  = "name,description\n" + rows
      io   = NonSeekableIO.new(csv)
      result = SmarterCSV.process(io, col_sep: :auto, row_sep: :auto, buffer_size: 32)
      expect(result.length).to eq(10)
      expect(result.first[:name]).to eq('item_1')
      expect(result.first[:description]).to eq("#{wide_value}_1")
      expect(result.last[:name]).to eq('item_10')
      expect(result.last[:description]).to eq("#{wide_value}_10")
    end
  end

  # ---------------------------------------------------------------------------
  # Quoted fields containing embedded newlines
  #
  # The C extension calls gets repeatedly for one logical row when a quoted field
  # spans multiple lines. PeekableIO's frozen-phase gets is exercised multiple
  # times per record, crossing the buffer/IO boundary within one CSV row.
  # ---------------------------------------------------------------------------
  describe 'quoted fields containing embedded newlines' do
    it 'parses multi-line quoted fields across buffer boundaries on NonSeekableIO' do
      csv = "name,bio\n" \
            "\"Alice\",\"line one\nline two\nline three\"\n" \
            "Bob,plain\n"
      io = NonSeekableIO.new(csv)
      result = SmarterCSV.process(io, col_sep: :auto, row_sep: :auto, buffer_size: 16)
      expect(result.length).to eq(2)
      expect(result.first[:name]).to eq('Alice')
      expect(result.first[:bio]).to eq("line one\nline two\nline three")
      expect(result.last[:name]).to eq('Bob')
      expect(result.last[:bio]).to eq('plain')
    end
  end

  # ---------------------------------------------------------------------------
  # Separator auto-detection matrix — all col_sep × row_sep on NonSeekableIO
  #
  # 5 col_seps × 3 row_seps = 15 combinations.
  # NonSeekableIO is the most constrained source (no rewind/seek) — if the buffer
  # correctly auto-detects all 15 combinations here, it works for any IO source.
  # ---------------------------------------------------------------------------
  # Run the entire matrix suite once per buffer size so every boundary scenario is
  # always exercised in CI, not just a randomly sampled one.
  INTERESTING_BUFFER_SIZES.each do |test_buffer_size|
    # Content is 20 rows × ~20 bytes ≈ 400 bytes — forces multiple buffer expansions,
    # exercising extend_buffer! during detection and frozen-phase delegation beyond the buffer.
    describe "separator auto-detection matrix — all col_sep × row_sep (buffer_size: #{test_buffer_size})" do
      col_seps    = [',', ';', "\t", '|', ':']
      row_sep_map = { 'LF' => "\n", 'CRLF' => "\r\n", 'CR' => "\r" }

      col_seps.each do |col_sep|
        col_label = col_sep == "\t" ? 'TAB' : col_sep.inspect
        row_sep_map.each do |row_label, row_sep|
          it "detects col_sep=#{col_label} row_sep=#{row_label}" do
            header = "name#{col_sep}value#{row_sep}"
            rows   = (1..20).map { |i| "item_#{i}#{col_sep}#{i * 10}#{row_sep}" }.join
            io = NonSeekableIO.new(header + rows)
            result = SmarterCSV.process(io, col_sep: :auto, row_sep: :auto, buffer_size: test_buffer_size)
            expect(result.length).to eq(20)
            expect(result.first).to eq({ name: 'item_1', value: 10 })
            expect(result.last).to  eq({ name: 'item_20', value: 200 })
          end
        end
      end
    end

    # Shared encoding test cases — used by both the Tempfile and NonSeekableIO encoding matrices.
    #
    # Each entry exercises a distinct transcoding code path:
    #   UTF-8            — baseline, no transcoding needed
    #   ISO-8859-1       — enforce_utf8_encoding path (single encoding, @enforce_utf8 = true)
    #   ISO-8859-1:UTF-8 — maybe_transcode path (transcoding pair, ext→int in PeekableIO)
    #   Windows-1252:UTF-8 — same, but \x80 = € (byte invalid in ISO-8859-1)
    #
    # make_bytes takes a row_sep argument so each case can be run with \n and \r\n.
    # ext_enc / int_enc are the encoding metadata the IO object should report.
    # Content: header + 20 data rows, non-ASCII chars appear throughout including
    # rows well beyond the buffer boundary, so transcoding must work for
    # bytes read from @io in the frozen phase, not just from the initial peek.
    encoding_cases = [
      {
        label: 'UTF-8 baseline',
        make_bytes: ->(rs) {
          rows = (1..20).map { |i| "name_#{i},München_#{i}#{rs}" }.join
          ("name,city#{rs}" + rows).encode('UTF-8').b
        },
        file_encoding: 'utf-8',
        ext_enc: 'UTF-8',
        int_enc: nil,
        expected: { name: 'name_1', city: 'München_1' },
        last_expected: { name: 'name_20', city: 'München_20' },
        quiet: false,
      },
      {
        label: 'ISO-8859-1 single encoding (enforce_utf8_encoding path)',
        make_bytes: ->(rs) {
          rows = (1..20).map { |i| "name_#{i},M\xFCnchen_#{i}#{rs}" }.join
          ("name,city#{rs}" + rows).b
        },
        file_encoding: 'iso-8859-1',
        ext_enc: 'ISO-8859-1',
        int_enc: nil,
        expected: { name: 'name_1', city: 'München_1' },
        last_expected: { name: 'name_20', city: 'München_20' },
        quiet: false,
      },
      {
        label: 'ISO-8859-1:UTF-8 transcoding pair (maybe_transcode path)',
        make_bytes: ->(rs) {
          rows = (1..20).map { |i| "name_#{i},M\xFCnchen_#{i}#{rs}" }.join
          ("name,city#{rs}" + rows).b
        },
        file_encoding: 'iso-8859-1:UTF-8',
        ext_enc: 'ISO-8859-1',
        int_enc: 'UTF-8',
        expected: { name: 'name_1', city: 'München_1' },
        last_expected: { name: 'name_20', city: 'München_20' },
        quiet: true,
      },
      {
        label: 'Windows-1252:UTF-8 transcoding pair (euro sign \\x80)',
        make_bytes: ->(rs) {
          rows = (1..20).map { |i| "item_#{i},\x80#{i * 100}#{rs}" }.join
          ("name,price#{rs}" + rows).b
        },
        file_encoding: 'Windows-1252:UTF-8',
        ext_enc: 'Windows-1252',
        int_enc: 'UTF-8',
        expected: { name: 'item_1', price: '€100' },
        last_expected: { name: 'item_20', price: '€2000' },
        quiet: true,
      },
    ]

    # ---------------------------------------------------------------------------
    # Encoding matrix — Tempfile (real file path), LF and CRLF row_sep
    #
    # Uses real Tempfiles so the file handle carries proper OS-level encoding
    # metadata, which drives the maybe_transcode / enforce_utf8 code paths.
    # Running each encoding with both \n and \r\n catches bugs where transcoding
    # corrupts bytes that look like separator characters.
    # ---------------------------------------------------------------------------
    describe "encoding matrix — Tempfile, LF and CRLF (buffer_size: #{test_buffer_size})" do
      def with_binary_tempfile(raw_bytes)
        t = Tempfile.new(['smarter_csv_enc', '.csv'])
        t.binmode
        t.write(raw_bytes)
        t.flush
        yield t.path
      ensure
        t.close
        t.unlink
      end

      { 'LF' => "\n", 'CRLF' => "\r\n" }.each do |row_label, row_sep|
        context "row_sep=#{row_label}" do
          encoding_cases.each do |enc|
            it enc[:label] do
              with_binary_tempfile(enc[:make_bytes].call(row_sep)) do |path|
                opts = { col_sep: :auto, row_sep: :auto, file_encoding: enc[:file_encoding], buffer_size: test_buffer_size }
                opts[:verbose] = :quiet if enc[:quiet]
                result = SmarterCSV.process(path, **opts)
                expect(result.length).to eq(20)
                enc[:expected].each do |key, val|
                  expect(result.first[key]).to eq(val)
                  expect(result.first[key].encoding).to eq(Encoding::UTF_8) if val.is_a?(String)
                end
                enc[:last_expected].each do |key, val|
                  expect(result.last[key]).to eq(val)
                  expect(result.last[key].encoding).to eq(Encoding::UTF_8) if val.is_a?(String)
                end
              end
            end
          end
        end
      end
    end

    # ---------------------------------------------------------------------------
    # Encoding matrix — EncodedBytesIO (non-seekable), LF and CRLF row_sep
    #
    # Same encoding variations but through a non-seekable IO source — the hardest
    # case: no rewind, the buffer must replay correctly including transcoding.
    # ---------------------------------------------------------------------------
    describe "encoding matrix — EncodedBytesIO non-seekable, LF and CRLF (buffer_size: #{test_buffer_size})" do
      { 'LF' => "\n", 'CRLF' => "\r\n" }.each do |row_label, row_sep|
        context "row_sep=#{row_label}" do
          encoding_cases.each do |enc|
            it enc[:label] do
              io = EncodedBytesIO.new(enc[:make_bytes].call(row_sep), enc[:ext_enc], enc[:int_enc])
              opts = { col_sep: :auto, row_sep: :auto, file_encoding: enc[:file_encoding], buffer_size: test_buffer_size }
              opts[:verbose] = :quiet if enc[:quiet]
              result = SmarterCSV.process(io, **opts)
              expect(result.length).to eq(20)
              enc[:expected].each do |key, val|
                expect(result.first[key]).to eq(val)
                expect(result.first[key].encoding).to eq(Encoding::UTF_8) if val.is_a?(String)
              end
              enc[:last_expected].each do |key, val|
                expect(result.last[key]).to eq(val)
                expect(result.last[key].encoding).to eq(Encoding::UTF_8) if val.is_a?(String)
              end
            end
          end
        end
      end
    end

    # ---------------------------------------------------------------------------
    # Encoding matrix — non-comma col_sep (;, TAB) × non-ASCII encodings
    #
    # Verifies that encoding + transcoding works regardless of col_sep.
    # 2 col_seps × 2 row_seps × 2 encoding cases = 8 tests.
    # ---------------------------------------------------------------------------
    describe "encoding matrix — non-comma col_sep with non-ASCII encodings (buffer_size: #{test_buffer_size})" do
      non_comma_encoding_cases = [
        { label: 'ISO-8859-1 single encoding (enforce_utf8_encoding path)',
          ext_enc: 'ISO-8859-1', int_enc: nil, file_encoding: 'iso-8859-1', quiet: false,
          make_bytes: ->(cs, rs) {
            rows = (1..20).map { |i| "name_#{i}#{cs}M\xFCnchen_#{i}#{rs}" }.join
            ("name#{cs}city#{rs}" + rows).b
          },
          expected: { city: 'München_1' },
          last_expected: { city: 'München_20' } },
        { label: 'ISO-8859-1:UTF-8 transcoding pair (maybe_transcode path)',
          ext_enc: 'ISO-8859-1', int_enc: 'UTF-8', file_encoding: 'iso-8859-1:UTF-8', quiet: true,
          make_bytes: ->(cs, rs) {
            rows = (1..20).map { |i| "name_#{i}#{cs}M\xFCnchen_#{i}#{rs}" }.join
            ("name#{cs}city#{rs}" + rows).b
          },
          expected: { city: 'München_1' },
          last_expected: { city: 'München_20' } },
      ]

      [';', "\t"].each do |col_sep|
        col_label = col_sep == "\t" ? 'TAB' : col_sep.inspect
        { 'LF' => "\n", 'CRLF' => "\r\n" }.each do |row_label, row_sep|
          context "col_sep=#{col_label} row_sep=#{row_label}" do
            non_comma_encoding_cases.each do |enc|
              it enc[:label] do
                io   = EncodedBytesIO.new(enc[:make_bytes].call(col_sep, row_sep), enc[:ext_enc], enc[:int_enc])
                opts = { col_sep: :auto, row_sep: :auto, file_encoding: enc[:file_encoding], buffer_size: test_buffer_size }
                opts[:verbose] = :quiet if enc[:quiet]
                result = SmarterCSV.process(io, **opts)
                expect(result.length).to eq(20)
                enc[:expected].each do |key, val|
                  expect(result.first[key]).to eq(val)
                  expect(result.first[key].encoding).to eq(Encoding::UTF_8) if val.is_a?(String)
                end
                enc[:last_expected].each do |key, val|
                  expect(result.last[key]).to eq(val)
                  expect(result.last[key].encoding).to eq(Encoding::UTF_8) if val.is_a?(String)
                end
              end
            end
          end
        end
      end
    end
  end # INTERESTING_BUFFER_SIZES.each

  # ---------------------------------------------------------------------------
  # buffer_size option flows through SmarterCSV.process
  #
  # buffer_size is read in reader.rb and passed to PeekableIO.new.  These tests
  # confirm that passing it as a SmarterCSV.process option produces correct
  # results across several sizes, including sizes small enough to force multiple
  # extend_buffer! calls during detection.
  # ---------------------------------------------------------------------------
  describe 'buffer_size option flowing through SmarterCSV.process' do
    it 'auto-detects separators correctly with a tiny buffer_size (forces many extend_buffer! calls)' do
      content = "name,value\n" + (1..20).map { |i| "item_#{i},#{i * 10}\n" }.join
      io = NonSeekableIO.new(content)
      result = SmarterCSV.process(io, col_sep: :auto, row_sep: :auto, buffer_size: 3)
      expect(result.length).to eq(20)
      expect(result.first).to eq({ name: 'item_1', value: 10 })
      expect(result.last).to  eq({ name: 'item_20', value: 200 })
    end

    it 'auto-detects separators correctly with a moderate buffer_size' do
      content = "name,value\n" + (1..20).map { |i| "item_#{i},#{i * 10}\n" }.join
      io = NonSeekableIO.new(content)
      result = SmarterCSV.process(io, col_sep: :auto, row_sep: :auto, buffer_size: 128)
      expect(result.length).to eq(20)
      expect(result.first).to eq({ name: 'item_1', value: 10 })
      expect(result.last).to  eq({ name: 'item_20', value: 200 })
    end

    it 'auto-detects separators correctly with buffer_size larger than the full content' do
      content = "name,value\n" + (1..5).map { |i| "item_#{i},#{i * 10}\n" }.join
      io = NonSeekableIO.new(content)
      result = SmarterCSV.process(io, col_sep: :auto, row_sep: :auto, buffer_size: 4096)
      expect(result.length).to eq(5)
      expect(result.first).to eq({ name: 'item_1', value: 10 })
    end

    it 'works correctly with buffer_size on a pipe (non-seekable)' do
      reader, writer = IO.pipe
      writer.write("name\tvalue\r\nitem_1\t10\r\nitem_2\t20\r\n")
      writer.close
      result = SmarterCSV.process(reader, col_sep: :auto, row_sep: :auto, buffer_size: 8)
      expect(result).to eq([{ name: 'item_1', value: 10 }, { name: 'item_2', value: 20 }])
    ensure
      reader.close unless reader.closed?
    end
  end
end
