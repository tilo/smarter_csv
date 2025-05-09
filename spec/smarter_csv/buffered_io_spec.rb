require 'smarter_csv/buffered_io'

RSpec.describe SmarterCSV::BufferedIO do
  let(:fixture_path) { 'spec/fixtures/test_buffered_io' }

  describe "initialize' do "
  it "reads all bytes from file and matches expected content" do
    io = SmarterCSV::BufferedIO.new(fixture_path, 256 * 1024)
    buffer = +""

    while (char = io.next_byte)
      buffer << char
    end

    expect(buffer).to eq("line1\nline2\nline3\n")
    expect(io.eof?).to eq(true)
  end
end
