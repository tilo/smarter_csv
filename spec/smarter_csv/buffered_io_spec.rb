# frozen_string_literal: true

require 'buffered_io/buffered_io'
require 'digest'

RSpec.describe SmarterCSV::BufferedIO do
  let(:fixture_path) { 'spec/fixtures/buffered_io' }

  describe 'initialize' do
    context "when reading files" do
      context 'with small buffer size' do
        let(:filename) { "#{fixture_path}/simple.csv" }
        [2, 3, 4, 16, 128].each do |buffer_size|
          it "reads all bytes from file and matches expected content with buffer size #{buffer_size}" do
            io = SmarterCSV::BufferedIO.new(filename, buffer_size)
            buffer = +""

            while (char = io.next_byte)
              buffer << char
            end

            expect(buffer).to eq("line1\nline2\nline3\n")
            expect(io.eof?).to eq(true)
          end
        end
      end

      context 'with large file' do
        let(:filename) { "#{fixture_path}/long_lines.csv" }
        let(:checksum) {  Digest::SHA2.hexdigest File.read(filename) }

        [512, 1024, 8096, 16_384].each do |buffer_size|
          it "reads all bytes from File and matches expected content with buffer size #{buffer_size}" do
            io = SmarterCSV::BufferedIO.new(filename, buffer_size)
            buffer = +""
            while (char = io.next_byte)
              buffer << char
            end
            expect(checksum).to eq(Digest::SHA2.hexdigest(buffer))
          end

          it "reads all bytes from Ruby IO and matches expected content with buffer size #{buffer_size}" do
            ruby_io = StringIO.new(File.read(filename))
            io = SmarterCSV::BufferedIO.new(ruby_io, buffer_size)
            buffer = +""
            while (char = io.next_byte)
              buffer << char
            end
            expect(checksum).to eq(Digest::SHA2.hexdigest(buffer))
          end
        end
      end
    end

    context 'corner cases' do
      it "handles an empty file gracefully" do
        filename = "#{fixture_path}/empty.csv"
        io = SmarterCSV::BufferedIO.new(filename, 16)
        expect(File.size?(filename))
        expect(io.next_byte).to be_nil
        expect(io.eof?).to eq(true)
      end

      it "handles file that ends exactly at buffer size" do
        filename = "#{fixture_path}/exact_128bytes.csv"
        content = "a"* 128
        File.write(filename, content)
        io = SmarterCSV::BufferedIO.new(filename, 128)
        result = +""
        while (b = io.next_byte)
          result << b
        end
        expect(result).to eq(content)
      end

      it "reads null bytes correctly" do
        input = "\x00abc\x00def\n"
        io = SmarterCSV::BufferedIO.new(StringIO.new(input), 4)
        result = +""
        while (b = io.next_byte)
          result << b
        end
        expect(result.bytes).to eq(input.bytes)
      end

      it "handles multi-byte UTF-8 characters across buffer boundaries" do
        # Emoji = 4-byte UTF-8: "💡💡💡" = 12 bytes
        input = "123💡💡💡456\n"
        io = SmarterCSV::BufferedIO.new(StringIO.new(input), 4)
        result = []
        while (b = io.next_byte)
          result += [b]
        end
        # we are doing low-level IO, we care only about bytes here, not encoding
        expect(result).to eq(input.bytes)
      end
    end
  end

  describe '#peek_byte' do
    it 'returns the same byte as next_byte without advancing' do
      io = SmarterCSV::BufferedIO.new(StringIO.new("ABC"), 2)

      first_peek = io.peek_byte
      expect(first_peek).to eq("A".ord)

      first_actual = io.next_byte
      expect(first_actual).to eq("A".ord)

      second_peek = io.peek_byte
      expect(second_peek).to eq("B".ord)
    end

    it 'returns nil at EOF' do
      io = SmarterCSV::BufferedIO.new(StringIO.new("Z"), 1)

      expect(io.peek_byte).to eq("Z".ord)
      expect(io.next_byte).to eq("Z".ord)
      expect(io.peek_byte).to be_nil
      expect(io.next_byte).to be_nil
    end
  end

  describe '#peek_bytes' do
    it 'returns all remaining bytes, if fewer are available' do
      io = SmarterCSV::BufferedIO.new(StringIO.new("abc"), 2)
      expect(io.peek_bytes(4)).to eq("abc".bytes)
      expect(io.next_byte).to eq("a".ord)
      expect(io.peek_bytes(3)).to eq("bc".bytes)
      expect(io.next_byte).to eq("b".ord)
      expect(io.next_byte).to eq("c".ord)
      expect(io.peek_bytes(1)).to be_nil
      expect(io.next_byte).to be_nil
    end

    it 'peeks multiple bytes without advancing' do
      io = SmarterCSV::BufferedIO.new(StringIO.new("abcdef"), 3)
      expect(io.peek_bytes(4)).to eq("abcd".bytes)
      expect(io.next_byte).to eq("a".ord)
      expect(io.peek_bytes(3)).to eq("bcd".bytes)
    end

    it 'returns partial result if fewer bytes available' do
      io = SmarterCSV::BufferedIO.new(StringIO.new("abc"), 2)
      expect(io.peek_bytes(5)).to eq("abc".bytes)
    end

    it 'returns nil at EOF' do
      io = SmarterCSV::BufferedIO.new(StringIO.new("z"), 1)
      expect(io.peek_bytes(1)).to eq(["z".ord])
      io.next_byte
      expect(io.peek_bytes(1)).to be_nil
    end

    it 'returns empty string when given 0' do
      io = SmarterCSV::BufferedIO.new(StringIO.new("hello"), 2)
      expect(io.peek_bytes(0)).to eq([])
    end

    it 'repeated peeks do not advance' do
      io = SmarterCSV::BufferedIO.new(StringIO.new("xyz"), 2)
      expect(io.peek_bytes(2)).to eq("xy".bytes)
      expect(io.peek_bytes(2)).to eq("xy".bytes)
      expect(io.next_byte).to eq("x".ord)
      expect(io.peek_bytes(2)).to eq("yz".bytes)
    end

    it 'handles peeking across buffer boundary without advancing' do
      io = SmarterCSV::BufferedIO.new(StringIO.new("1234567890"), 4)
      expect(io.peek_bytes(8)).to eq("12345678".bytes)
      expect(io.next_byte).to eq("1".ord)
      expect(io.peek_bytes(3)).to eq("234".bytes)
    end
  end
end
