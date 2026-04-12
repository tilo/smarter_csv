# frozen_string_literal: true

require 'spec_helper'
require 'stringio'

RSpec.describe SmarterCSV::PeekableIO do
  let(:content) { "header1,header2\nval1,val2\nval3,val4\n" }
  let(:io)      { StringIO.new(content) }
  subject(:pio) { described_class.new(io) }

  # ---------------------------------------------------------------------------
  # Buffer lifecycle
  # ---------------------------------------------------------------------------
  describe 'buffer lifecycle' do
    it 'peek_buf is nil before peek is called' do
      expect(pio.instance_variable_get(:@peek_buf)).to be_nil
    end

    it 'peek_buf is set after peek' do
      pio.peek(16_384)
      expect(pio.instance_variable_get(:@peek_buf)).not_to be_nil
    end

    it 'peek_buf is nil (released) after buffer is fully drained via read' do
      pio.peek(16_384)
      pio.read
      expect(pio.instance_variable_get(:@peek_buf)).to be_nil
    end

    it 'peek_buf is nil after buffer is fully drained via gets' do
      pio.peek(16_384)
      pio.gets("\n") until pio.eof?
      expect(pio.instance_variable_get(:@peek_buf)).to be_nil
    end
  end

  # ---------------------------------------------------------------------------
  # #peek
  # ---------------------------------------------------------------------------
  describe '#peek' do
    it 'returns the peeked bytes as a string' do
      result = pio.peek(10)
      expect(result).to eq(content[0, 10])
    end

    it 'does not lose any data on subsequent gets' do
      pio.peek(16_384)
      expect(pio.gets("\n")).to eq("header1,header2\n")
      expect(pio.gets("\n")).to eq("val1,val2\n")
      expect(pio.gets("\n")).to eq("val3,val4\n")
    end

    it 'replays a partial peek correctly when sep spans the buffer boundary' do
      pio.peek(7)  # "header1" — does not include the newline
      expect(pio.gets("\n")).to eq("header1,header2\n")
    end
  end

  # ---------------------------------------------------------------------------
  # #gets / #readline
  # ---------------------------------------------------------------------------
  describe '#gets' do
    it 'replays all peeked bytes before reading from underlying IO' do
      pio.peek(16_384)
      lines = []
      lines << pio.gets("\n") until pio.eof?
      expect(lines).to eq(["header1,header2\n", "val1,val2\n", "val3,val4\n"])
    end

    it 'returns nil at EOF' do
      pio.peek(16_384)
      pio.read
      expect(pio.gets("\n")).to be_nil
    end
  end

  describe '#readline' do
    it 'is an alias for gets' do
      pio.peek(16_384)
      expect(pio.readline("\n")).to eq("header1,header2\n")
    end
  end

  # ---------------------------------------------------------------------------
  # #read
  # ---------------------------------------------------------------------------
  describe '#read' do
    it 'returns all content after a full peek' do
      pio.peek(16_384)
      expect(pio.read).to eq(content)
    end

    it 'returns all content without any peek' do
      expect(pio.read).to eq(content)
    end
  end

  # ---------------------------------------------------------------------------
  # #each_char
  # ---------------------------------------------------------------------------
  describe '#each_char' do
    it 'replays peeked bytes then continues from underlying IO' do
      pio.peek(8)
      chars = []
      pio.each_char { |c| chars << c }
      expect(chars.join).to eq(content)
    end

    it 'works without peek' do
      chars = []
      pio.each_char { |c| chars << c }
      expect(chars.join).to eq(content)
    end
  end

  # ---------------------------------------------------------------------------
  # #rewind
  # ---------------------------------------------------------------------------
  describe '#rewind' do
    it 'replays the buffer from the start (simulates rewind without touching underlying IO)' do
      pio.peek(16_384)
      pio.gets("\n")  # consume first line
      pio.rewind
      expect(pio.gets("\n")).to eq("header1,header2\n")  # replayed
    end

    it 'can be called multiple times' do
      pio.peek(16_384)
      3.times { pio.rewind }
      expect(pio.gets("\n")).to eq("header1,header2\n")
    end
  end

  # ---------------------------------------------------------------------------
  # #eof?
  # ---------------------------------------------------------------------------
  describe '#eof?' do
    it 'is false while peek buffer has unread bytes' do
      pio.peek(16_384)
      expect(pio.eof?).to be false
    end

    it 'is true after all content is consumed' do
      pio.peek(16_384)
      pio.read
      expect(pio.eof?).to be true
    end

    it 'is true on an empty source' do
      empty_pio = described_class.new(StringIO.new(''))
      expect(empty_pio.eof?).to be true
    end
  end

  # ---------------------------------------------------------------------------
  # #external_encoding
  # ---------------------------------------------------------------------------
  describe '#external_encoding' do
    it 'delegates to the underlying IO' do
      enc_io = StringIO.new(content)
      enc_io.set_encoding(Encoding::ISO_8859_1)
      pio = described_class.new(enc_io)
      expect(pio.external_encoding).to eq(Encoding::ISO_8859_1)
    end

    it 'returns nil when underlying IO does not respond to external_encoding' do
      bare = Object.new
      allow(bare).to receive(:respond_to?).with(:external_encoding).and_return(false)
      pio = described_class.new(bare)
      expect(pio.external_encoding).to be_nil
    end
  end
end
