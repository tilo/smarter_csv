require 'bacon'

$:.unshift File.join(File.dirname(__FILE__), '..', 'lib')
require 'smarter_csv'

describe 'Parsing CSV with different encoding' do
  it 'should be able to specofy encoding' do
    file = File.expand_path('../encodings_example_windows-1251.csv', __FILE__)
    data = SmarterCSV.process(file, :source_encoding => 'windows-1251')

    data_utf = SmarterCSV.process(File.expand_path('../encodings_example.csv', __FILE__))

    data_utf[0][:person].should == data[0][:person]
  end
end