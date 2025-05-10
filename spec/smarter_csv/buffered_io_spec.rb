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
        content = "a" * 128
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
        result = +""
        while (b = io.next_byte)
          result << b
        end
        # we are doing low-level IO, we care only about bytes here, not encoding
        expect(result.bytes).to eq(input.bytes)
      end
    end
  end
end
