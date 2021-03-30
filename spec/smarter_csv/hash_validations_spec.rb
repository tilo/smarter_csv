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

  it 'does required_fields_matching' do
    # this requires emails matching domain bla.com, with one word in front
    # this requires employee_id to start with a sequence of zeros
    # this requires first_name and last_name to be words
    options = {
      hash_validations: [
        required_fields_matching: {
          first_name: /\A[[:word:]]+\z/, last_name: /\A[[:word:]]+\z/, employee_id: /\A0+\d+\z/,
          email: /\A\w+@bla.com\z/, manager_email: /\A\w+@bla.com\z/
        }
      ]
    }
    data = SmarterCSV.process("#{fixture_path}/user_import_bad.csv", options)

    data.size.should eq 3
    SmarterCSV.errors.keys.size.should eq 2
    SmarterCSV.errors.should eq({
      2=>["Field `:manager_email` in CSV line 2: `tom@blubb.com` did not match /\\A\\w+@bla.com\\z/"],
      5=>["Field `:employee_id` in CSV line 5: `17` did not match /\\A0+\\d+\\z/", "Field `:email` in CSV line 5: `danny.0000@bla.com` did not match /\\A\\w+@bla.com\\z/"]
    })
    SmarterCSV.warnings.should eq Hash.new
  end

  it 'should validate first_name with size greater than 3 using custom validation' do
    custom_validation = Proc.new{|hash|
      errors = []
      if hash.key?(:first_name) && hash[:first_name].size < 4
        errors << "first name must be greater than 3"
      end
      errors
    }

    options = {
      hash_validations: [ custom_validation ]
    }

    data = SmarterCSV.process("#{fixture_path}/basic.csv", options)

    data.size.should eq 4
    SmarterCSV.errors.keys.size.should eq 1
    SmarterCSV.errors.should eq({
      2=>["first name must be greater than 3"],
    })
  end
end
