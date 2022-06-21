# frozen_string_literal: true

require 'spec_helper'

fixture_path = 'spec/fixtures'

describe 'no header in file' do
  let(:headers) { [:a, :b, :c, :d, :e, :f] }
  let(:options) { {:headers_in_file => false, :user_provided_headers => headers} }
  subject(:data) { SmarterCSV.process("#{fixture_path}/no_header.csv", options) }

  it 'load the correct number of records' do
    data.size.should == 5
  end

  it 'uses given symbols for all records' do
    data.each do |item|
      item.keys.each do |key|
        [:a, :b, :c, :d, :e, :f].should include(key)
      end
    end
  end

  it 'loads the correct data' do
    data[0].should == {a: "Dan", b: "McAllister", c: 2, d: 0}
    data[1].should == {a: "Lucy", b: "Laweless", d: 5, e: 0}
    data[2].should == {a: "Miles", b: "O'Brian", c: 0, d: 0, e: 0, f: 21}
    data[3].should == {a: "Nancy", b: "Homes", c: 2, d: 0, e: 1}
    data[4].should == {a: "Hernán", b: "Curaçon", c: 3, d: 0, e: 0}
  end
end
