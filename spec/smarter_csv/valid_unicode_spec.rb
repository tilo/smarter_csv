require 'spec_helper'

fixture_path = 'spec/fixtures'

describe 'be_able_to' do


  it 'loads file with unicode strings' do
    options = {}
    data = SmarterCSV.process("#{fixture_path}/valid_unicode.csv", options)
    data.flatten.size.should == 4
    data[0][:artist].should eq 'Кино'
    data[0][:track].should eq 'Мама, мы все сошли с ума'
    data[0][:album].should eq 'Группа Крови'
    data[0][:label].should eq 'Moroz Records'
    data[0][:year].should eq 1998

    data[0].should eq  data[1]

    data[2][:artist].should eq 'Rammstein'
    data[2][:track].should eq 'Frühling in Paris'
    data[2][:album].should eq 'Liebe ist für alle da'
    data[2][:label].should eq 'Vagrant'
    data[2][:year].should eq 2009

    data[2].should eq  data[3]
  end

  it 'loads file with unicode strings, when forcing utf8' do
    options = {:force_utf8 => true}
    data = SmarterCSV.process("#{fixture_path}/valid_unicode.csv", options)
    data.flatten.size.should == 4
    data[0][:artist].should eq 'Кино'
    data[0][:track].should eq 'Мама, мы все сошли с ума'
    data[0][:album].should eq 'Группа Крови'
    data[0][:label].should eq 'Moroz Records'
    data[0][:year].should eq 1998

    data[0].should eq  data[1]

    data[2][:artist].should eq 'Rammstein'
    data[2][:track].should eq 'Frühling in Paris'
    data[2][:album].should eq 'Liebe ist für alle da'
    data[2][:label].should eq 'Vagrant'
    data[2][:year].should eq 2009

    data[2].should eq  data[3]
  end



  it 'loads file with unicode strings, when loading from binary input' do
    options = {:file_encoding => 'binary'}
    data = SmarterCSV.process("#{fixture_path}/valid_unicode.csv", options)
    data.flatten.size.should == 4
    data[0][:artist].should eq 'Кино'
    data[0][:track].should eq 'Мама, мы все сошли с ума'
    data[0][:album].should eq 'Группа Крови'
    data[0][:label].should eq 'Moroz Records'
    data[0][:year].should eq 1998

    data[0].should eq  data[1]

    data[2][:artist].should eq 'Rammstein'
    data[2][:track].should eq 'Frühling in Paris'
    data[2][:album].should eq 'Liebe ist für alle da'
    data[2][:label].should eq 'Vagrant'
    data[2][:year].should eq 2009

    data[2].should eq  data[3]
  end

  it 'loads file with unicode strings, when forcing utf8 with binary input' do
    options = {:file_encoding => 'binary', :force_utf8 => true}
    data = SmarterCSV.process("#{fixture_path}/valid_unicode.csv", options)
    data.flatten.size.should == 4
    data[0][:artist].should eq 'Кино'
    data[0][:track].should eq 'Мама, мы все сошли с ума'
    data[0][:album].should eq 'Группа Крови'
    data[0][:label].should eq 'Moroz Records'
    data[0][:year].should eq 1998

    data[0].should eq  data[1]

    data[2][:artist].should eq 'Rammstein'
    data[2][:track].should eq 'Frühling in Paris'
    data[2][:album].should eq 'Liebe ist für alle da'
    data[2][:label].should eq 'Vagrant'
    data[2][:year].should eq 2009

    data[2].should eq  data[3]
  end

end
