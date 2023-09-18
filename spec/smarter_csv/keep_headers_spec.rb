# frozen_string_literal: true

require 'spec_helper'

fixture_path = 'spec/fixtures'

describe 'be_able_to' do
  it 'not_downcase_headers' do
    options = {defaults: :no_procs}
    data = SmarterCSV.process("#{fixture_path}/basic.csv", options)
    data.size.should == 5
    # all the keys should be string
    data.each{|item| item.each_key{|x| x.class.should be == String}}

    data.each do |item|
      item.each_key do |key|
        ['First Name', 'Last Name', 'Dogs', 'Cats', 'Birds', 'Fish'].should include(key)
      end
    end

    data.each do |h|
      h.size.should <= 6
    end
  end
end
