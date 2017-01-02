class Hash

  # Example:
  #     Hash.zip(["a", "b", "c"], [1, 2, 3])
  #     # => { "a" => 1, "b" => 2, "c" => 3 }
  def self.zip(keys, values)
    self[keys.zip(values)]
  end
end
