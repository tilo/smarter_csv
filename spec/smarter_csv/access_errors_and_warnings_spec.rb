require 'spec_helper'

fixture_path = 'spec/fixtures'

describe 'access errors and warnings' do
  describe 'hash_validations' do
    it 'allow user-defined Proc to add errors' do

      no_cats = Proc.new {|hash|
        count = 0
        if hash.has_key?(:cats)
          @errors[ @file_line_count ] ||= []
          @errors[ @file_line_count ] << "Invalid column `:cats` is set on CSV line #{@file_line_count}"
          count += 1
        end
        count
      }

      options = {
        hash_validations: [no_cats]
      }
      data = SmarterCSV.process("#{fixture_path}/basic.csv", options)

      data.size.should eq 0 # no line passes validation
      SmarterCSV.errors.keys.size.should eq 5
      SmarterCSV.errors.should eq({
        2=>["Invalid column `:cats` is set on CSV line 2"],
        3=>["Invalid column `:cats` is set on CSV line 3"],
        5=>["Invalid column `:cats` is set on CSV line 5"],
        6=>["Invalid column `:cats` is set on CSV line 6"],
        7=>["Invalid column `:cats` is set on CSV line 7"],
      })
      SmarterCSV.warnings.should eq({4=>["No data in line 4"], 8=>["No data in line 8"]})
    end

    it 'allow user-defined Proc to add warnings' do

      low_on_cats = Proc.new {|hash|
        count = 0
        if hash.has_key?(:cats) && hash[:cats].to_i < 2
          @warnings[ @file_line_count ] ||= []
          @warnings[ @file_line_count ] << "Low on cats on CSV line #{@file_line_count}"
          count += 1
        end
        count
      }

      options = {
        hash_validations: [low_on_cats]
      }
      data = SmarterCSV.process("#{fixture_path}/basic.csv", options)

      data.size.should eq 1 # only one line passes validation
      data.should eq([{first_name: "Lucy", last_name: "Laweless", cats: "5", birds: "0"}])
      SmarterCSV.warnings.keys.size.should eq 6
      SmarterCSV.warnings.should eq({
        2=>["Low on cats on CSV line 2"],
        4=>["No data in line 4"],
        5=>["Low on cats on CSV line 5"],
        6=>["Low on cats on CSV line 6"],
        7=>["Low on cats on CSV line 7"],
        8=>["No data in line 8"],
      })
      SmarterCSV.errors.should eq({})
    end
  end
end
