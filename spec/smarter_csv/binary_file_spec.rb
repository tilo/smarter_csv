# frozen_string_literal: true

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
      col_sep: "\cA", row_sep: "\cB", comment_regexp: /^#/,
      defaults: 'v1'
    }
    data = SmarterCSV.process("#{fixture_path}/binary.csv", options)

    data.flatten.size.should eq 8
    data.each do |item|
      # all keys should be symbols when using v1.x backwards compatible mode
      item.each_key{|x| x.class.should eq Symbol}
      item[:timestamp].should eq 1_381_388_409

      # Ruby 2.4+ unifies Fixnum & Bignum into Integer.
      if 0.class == Integer
        item[:item_id].class.should eq Integer
      else
        item[:item_id].class.should eq Integer
      end

      item[:name].size.should be > 0
    end
    data[3][:parent_id].should be_nil
    data[4][:parent_id].should be_nil
  end

  it 'with symbols as keys when using new defaults' do
    # new default is to have symbols as keys, so nothing to do for that
    # we have to remove blank values explicitly

    options = {
      col_sep: "\cA", row_sep: "\cB", comment_regexp: /^#/,
    }
    data = SmarterCSV.process("#{fixture_path}/binary.csv", options)

    data.flatten.size.should eq 8
    data.each do |item|
      # all keys should be symbols when using v1.x backwards compatible mode
      item.each_key{|x| x.class.should eq Symbol}
      item[:timestamp].should eq '1381388409'
      item[:item_id].class.should eq String
      item[:name].size.should be > 0
    end
    data[3][:parent_id].should be_nil
    data[4][:parent_id].should be_nil
  end

  it 'loads binary file with strings as keys' do
    # new default is to have symbols as keys, so nothing to do for that

    options = {
      col_sep: "\cA", row_sep: "\cB", comment_regexp: /^#/,
      header_transformations: [:none, :keys_as_strings],
      hash_transformations: [convert_values_to_numeric: %w[timestamp item_id parent_id]]
    }
    data = SmarterCSV.process("#{fixture_path}/binary.csv", options)

    data.flatten.size.should eq 8
    data.each do |item|
      # all keys should be strings
      item.each_key{|x| x.class.should eq String}
      item['timestamp'].should eq 1_381_388_409

      # Ruby 2.4+ unifies Fixnum & Bignum into Integer.
      if 0.class == Integer
        item['item_id'].class.should eq Integer
      else
        item['item_id'].class.should eq Integer
      end

      item['name'].size.should be > 0
    end
    data[3]['parent_id'].should be_nil
    data[4]['parent_id'].should be_nil
  end

  it 'with symbols as keys when requested' do
    # new default is to have symbols as keys, so we have to specifically enable this
    # we have to remove blank values explicitly

    options = {
      col_sep: "\cA", row_sep: "\cB", comment_regexp: /^#/,
      header_transformations: [:none, :keys_as_symbols],
      hash_transformations: [:remove_blank_values, {convert_values_to_numeric: [:timestamp, :item_id, :parent_id]}]
    }
    data = SmarterCSV.process("#{fixture_path}/binary.csv", options)

    data.flatten.size.should eq 8
    data.each do |item|
      # all keys should be symbols
      item.each_key{|x| x.class.should eq Symbol}
      item[:timestamp].should eq 1_381_388_409

      # Ruby 2.4+ unifies Fixnum & Bignum into Integer.
      if 0.class == Integer
        item[:item_id].class.should eq Integer
      else
        item[:item_id].class.should eq Integer
      end

      item[:name].size.should be > 0
    end
    data[3][:parent_id].should be_nil
    data[4][:parent_id].should be_nil
  end
end
