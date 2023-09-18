# frozen_string_literal: true

require 'spec_helper'

fixture_path = 'spec/fixtures'

describe 'strip spaces from headers' do
  it 'does not strip spaces from headers by default' do
    data = SmarterCSV.process("#{fixture_path}/basic.csv")
    data.size.should eq 5

    data.each do |item|
      item.each_key do |key|
        key.class.should eq Symbol
        [:first_name, :last_name, :dogs, :cats, :birds, :fish].should include(key)
      end
    end
  end

  it 'strips whitespace from headers with user-defined Proc' do
    strip_space = proc do |headers|
      headers.map { |x| x.gsub(/\s+/, '') }
    end

    options = {
      header_transformations: [:none, strip_space, :keys_as_symbols]
    }
    data = SmarterCSV.process("#{fixture_path}/basic.csv", options)
    data.size.should eq 5

    data.each do |item|
      item.each_key do |key|
        key.class.should eq Symbol
        [:firstname, :lastname, :dogs, :cats, :birds, :fish].should include(key)
      end
      item.size.should <= 6
    end
  end
end
