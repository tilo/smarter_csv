# frozen_string_literal: true

require 'spec_helper'

fixture_path = 'spec/fixtures'

describe 'strings as keys' do
  it 'does not use strings as keys by default' do
    data = SmarterCSV.process("#{fixture_path}/basic.csv")
    data.size.should eq 5

    data.each do |item|
      item.each_key do |key|
        key.class.should eq Symbol
      end
    end
  end

  it 'does use strings as keys when specifically asked' do
    options = {
      header_transformations: [:none, :keys_as_strings]
    }
    data = SmarterCSV.process("#{fixture_path}/basic.csv", options)
    data.size.should eq 5

    data.each do |item|
      item.each_key do |key|
        key.class.should eq String
        %w[first_name last_name dogs cats birds fish].should include(key)
      end
    end

    data.each do |h|
      h.size.should <= 6
    end
  end
end
