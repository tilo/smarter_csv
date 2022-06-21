# frozen_string_literal: true

require 'spec_helper'

fixture_path = 'spec/fixtures'

# according to RFC-4180 quotes inside of "words" shouldbe doubled, but our parser is robust against that.
describe 'malformed CSV quotes' do
  context "malformed quotes in header" do
    let(:csv_path) { "#{fixture_path}/malformed_header.csv" }
    it 'should be resilient against single quotes' do
      data = SmarterCSV.process(csv_path)
      expect(data[0]).to eq({:name=>"Arnold Schwarzenegger", :dobdob=>"1947-07-30"})
      expect(data[1]).to eq({:name=>"Jeff Bridges", :dobdob=>"1949-12-04"})
    end
  end

  context "malformed quotes in content" do
    let(:csv_path) { "#{fixture_path}/malformed.csv" }

    it 'should be resilient against single quotes' do
      data = SmarterCSV.process(csv_path)
      expect(data[0]).to eq({:name=>"Arnold Schwarzenegger", :dob=>"1947-07-30"})
      expect(data[1]).to eq({:name=>"Jeff \"the dude\" Bridges", :dob=>"1949-12-04"})
    end
  end
end
