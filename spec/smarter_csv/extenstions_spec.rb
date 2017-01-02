require 'spec_helper'

describe "Hash.zip" do
  it "constructs a new Hash from two Arrays" do
    Hash.zip(["a", "b"], [1, 2]).should == { "a" => 1, "b" => 2 }
  end

  it "constructs an empty Hash if given no keys" do
    Hash.zip([], []).should == {}
    Hash.zip([], [1]).should == {}
  end

  it "uses nil values if there are more keys than values" do
    Hash.zip(["a"], []).should == { "a" => nil }
    Hash.zip(["a", "b"], [1]).should == { "a" => 1, "b" => nil }
  end
end
