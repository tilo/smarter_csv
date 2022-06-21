# frozen_string_literal: true

require 'spec_helper'

fixture_path = 'spec/fixtures'

describe 'be_able_to' do
  it 'not_downcase_headers' do
    options = {downcase_header: false}
    data = SmarterCSV.process("#{fixture_path}/basic.csv", options)
    data.size.should == 5
    # all the keys should be symbols
    data.each{|item| item.each_key{|x| x.class.should be == Symbol}}

    data.each do |item|
      item.each_key do |key|
        %i[First_Name Last_Name Dogs Cats Birds Fish].should include(key)
      end
    end

    data.each do |h|
      h.size.should <= 6
    end
  end
end
