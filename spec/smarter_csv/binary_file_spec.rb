require 'spec_helper'

fixture_path = 'spec/fixtures'

# this reads a binary database dump file, which is in structure like a CSV file
# but contains control characters delimiting the rows and columns, and also
# contains a comment section which is commented our by a leading # character

describe 'loads binary file format with comments' do

  it 'with symbols as keys when using v1 defaults' do
    # old default is to have symbols as keys
    # old default is to automatically remove blank values

    options = {
      :col_sep => "\cA", :row_sep => "\cB", :comment_regexp => /^#/,
      :defaults => 'v1'
    }
    data = SmarterCSV.process("#{fixture_path}/binary.csv", options)

    data.flatten.size.should == 8
    data.each do |item|
      # all keys should be symbols when using v1.x backwards compatible mode
      item.keys.each{|x| x.class.should be == Symbol}
      item[:timestamp].should == 1381388409
      item[:item_id].class.should be == Fixnum
      item[:name].size.should be > 0
    end
    data[3][:parent_id].should be_nil
    data[4][:parent_id].should be_nil
  end

  it 'with symbols as keys when using safe defaults' do
    # new default is to keep strings as keys, so nothing to do for that
    # we have to remove blank values explicitly

    options = {
      :col_sep => "\cA", :row_sep => "\cB", :comment_regexp => /^#/,
      :defaults => 'safe'
    }
    data = SmarterCSV.process("#{fixture_path}/binary.csv", options)

    data.flatten.size.should == 8
    data.each do |item|
      # all keys should be symbols when using v1.x backwards compatible mode
      item.keys.each{|x| x.class.should be == Symbol}
      item[:timestamp].should == 1381388409
      item[:item_id].class.should be == Fixnum
      item[:name].size.should be > 0
    end
    data[3][:parent_id].should be_nil
    data[4][:parent_id].should be_nil
  end


  it 'loads binary file with strings as keys' do
    # new default is to keep strings as keys, so nothing to do for that
    # we have to remove blank values explicitly

    options = {
      :col_sep => "\cA", :row_sep => "\cB", :comment_regexp => /^#/ ,
      :hash_transformations => [ :remove_blank_values, convert_values_to_numeric: ['timestamp','item_id','parent_id'] ]
    }
    data = SmarterCSV.process("#{fixture_path}/binary.csv", options)

    data.flatten.size.should == 8
    data.each do |item|
      # all keys should be strings
      item.keys.each{|x| x.class.should be == String}
      item['timestamp'].should == 1381388409
      item['item_id'].class.should be == Fixnum
      item['name'].size.should be > 0
    end
    data[3]['parent_id'].should be_nil
    data[4]['parent_id'].should be_nil
  end


  it 'with symbols as keys when requested' do
    # new default is to keep strings as keys, so we have to specifically enable this
    # we have to remove blank values explicitly

    options = {
      :col_sep => "\cA", :row_sep => "\cB", :comment_regexp => /^#/,
      :header_transformations => [ :keys_as_symbols ],
      :hash_transformations => [ :remove_blank_values, convert_values_to_numeric: [:timestamp,:item_id,:parent_id] ]
    }
    data = SmarterCSV.process("#{fixture_path}/binary.csv", options)

    data.flatten.size.should == 8
    data.each do |item|
      # all keys should be symbols
      item.keys.each{|x| x.class.should be == Symbol}
      item[:timestamp].should == 1381388409
      item[:item_id].class.should be == Fixnum
      item[:name].size.should be > 0
    end
    data[3][:parent_id].should be_nil
    data[4][:parent_id].should be_nil
  end
end
