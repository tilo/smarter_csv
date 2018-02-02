require 'spec_helper'

fixture_path = 'spec/fixtures'

describe 'not downcasing headers' do

  it 'not_downcase_headers' do
    options = {
      header_transformations: [:none]
    }
    data = SmarterCSV.process("#{fixture_path}/basic.csv", options)
    data.size.should eq 5
    # all the keys should be symbols
    data.each do |item|
      item.keys.each do |x|
        x.class.should eq String
      end
    end

    data.each do |item|
      item.keys.each do |key|
        ["First Name", "Last Name", "Dogs", "Cats", "Birds", "Fish"].should include( key )
      end
    end

    data.each do |h|
      h.size.should <= 6
    end
  end

end
