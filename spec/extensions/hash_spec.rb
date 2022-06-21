# frozen_string_literal: true

require 'spec_helper'
require './lib/extensions/hash'

describe 'hash extensions' do
  let(:keys) { %i[a b] }
  let(:values) { [1, 2] }

  it 'calls Array.zip' do
    expect(keys).to receive(:zip).with(values)
    Hash.zip(keys, values)
  end

  it 'creates a hash from two arrays' do
    expect(Hash.zip([], [])).to eq({})
  end

  it 'creates a hash from two arrays' do
    expect(Hash.zip(%i[a b], [1, 2])).to eq({a: 1, b: 2})
  end

  it "constructs an empty Hash if given no keys" do
    Hash.zip([], []).should == {}
    Hash.zip([], [1]).should == {}
  end

  it "uses nil values if there are more keys than values" do
    Hash.zip(["a"], []).should == { "a" => nil }
    Hash.zip(%w[a b], [1]).should == { "a" => 1, "b" => nil }
  end
end
