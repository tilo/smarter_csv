# frozen_string_literal: true

require 'spec_helper'

fixture_path = 'spec/fixtures'

describe 'CSV files without header' do
  it 'should allow to manually define the header and read all CSV lines' do
    options = {headers_in_file: false, user_provided_headers: [:a, :b, :c, :d, :e, :f]}
    data = SmarterCSV.process("#{fixture_path}/no_header.csv", options)
    data.size.should eq 5
    # all the keys should be symbols
    data.each{|item| item.each_key{|x| x.class.should eq Symbol}}

    data.each do |item|
      item.each_key do |key|
        [:a, :b, :c, :d, :e, :f].should include(key)
      end
    end

    data.each do |h|
      h.size.should <= 6
    end
  end
end
