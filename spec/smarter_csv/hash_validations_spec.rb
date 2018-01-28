require 'spec_helper'

fixture_path = 'spec/fixtures'

describe 'hash validations' do

  it 'should read all lines if no validation was given' do
    data = SmarterCSV.process("#{fixture_path}/basic.csv")

    data.size.should eq 5
    SmarterCSV.errors.keys.size.should eq 0
    SmarterCSV.errors.should eq Hash.new
    SmarterCSV.warnings.should eq({4=>["No data in line 4"], 8=>["No data in line 8"]})
  end

  it 'should validate each line, returning only matching lines' do
    options = {
      hash_validations: [required_fields: [:cats,:fish]]
    }
    data = SmarterCSV.process("#{fixture_path}/basic.csv", options)

    data.size.should eq 0 # no line passes validation
    SmarterCSV.errors.keys.size.should eq 5
    SmarterCSV.errors.should eq({
      2=>["Missing required field `:cats` in CSV line 2", "Missing required field `:fish` in CSV line 2"],
      3=>["Missing required field `:fish` in CSV line 3"],
      5=>["Missing required field `:cats` in CSV line 5"],
      6=>["Missing required field `:cats` in CSV line 6", "Missing required field `:fish` in CSV line 6"],
      7=>["Missing required field `:cats` in CSV line 7", "Missing required field `:fish` in CSV line 7"]
    })
    SmarterCSV.warnings.should eq({4=>["No data in line 4"], 8=>["No data in line 8"]})
  end

end
