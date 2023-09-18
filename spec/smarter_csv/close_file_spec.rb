# frozen_string_literal: true

require 'spec_helper'

fixture_path = 'spec/fixtures'

describe 'be_able_to' do
  it 'close file after using it' do
    options = {col_sep: "\cA", row_sep: "\cB", comment_regexp: /^#/}

    file = File.new("#{fixture_path}/binary.csv")

    SmarterCSV.process(file, options)

    file.closed?.should eq true
  end
end
