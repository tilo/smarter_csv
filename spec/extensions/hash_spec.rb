require 'spec_helper'
require './lib/extensions/hash.rb'

describe 'hash extensions' do
  let(:keys) { [:a, :b] }
  let(:values) { [1, 2] }

  it 'calls Array.zip' do
    expect(keys).to receive(:zip).with(values)
    Hash.zip(keys, values)
  end

  it 'creates a hash from two arrays' do
    expect(Hash.zip([], [])).to eq Hash.new
  end

  it 'creates a hash from two arrays' do
    expect(Hash.zip([:a, :b], [1, 2])).to eq({a: 1, b: 2})
  end
end
