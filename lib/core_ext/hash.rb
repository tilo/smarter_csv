# the following extension for class Hash is needed (from Facets of Ruby library):

class Hash
  def self.zip(keys,values) # from Facets of Ruby library
    (keys.zip(values)).to_h
  end
end
