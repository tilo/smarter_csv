# frozen_string_literal: true

require 'pathname'

fixture_path = 'spec/fixtures'

describe 'file operations' do
  it 'close file after using it' do
    options = {col_sep: "\cA", row_sep: "\cB", comment_regexp: /^#/, strings_as_keys: true}

    file = File.new("#{fixture_path}/binary.csv")

    SmarterCSV.process(file, options)

    expect(file.closed?).to eq true
  end

  # A file SmarterCSV opens itself (from a path it was handed) must be closed when
  # processing finishes — same lifecycle as a caller-supplied IO. The close at
  # reader.rb is keyed on respond_to?(:close), not on the input type, so a String
  # path and a Pathname both open and close identically.
  { 'String path' => ->(p) { p }, 'Pathname' => ->(p) { Pathname.new(p) } }.each do |label, wrap|
    it "closes a file it opens itself from a #{label}" do
      opened = nil
      allow(File).to receive(:open).and_wrap_original do |orig, *args, **kwargs|
        opened = orig.call(*args, **kwargs)
      end

      SmarterCSV.process(wrap.call("#{fixture_path}/basic.csv"))

      expect(opened).to be_a(File)
      expect(opened.closed?).to eq true
    end
  end
end
