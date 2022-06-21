require 'spec_helper'

fixture_path = 'spec/fixtures'

[true, false].each do |bool|

  describe "fulfills basic tests with#{bool ? ' C-' : 'out '}acceleration" do
    let(:options) { { acceleration: bool } }

    describe 'basic CSV processing' do
      # works only when testing locally
      unless ENV['CI']
        it 'compiles the acceleration' do
          expect(SmarterCSV.has_acceleration?).to eq true
        end
      end

      it 'loads_basic_csv_file' do
        data = SmarterCSV.process("#{fixture_path}/basic.csv", options)
        data.size.should == 5

        # all the keys should be symbols
        data.each{|item| item.keys.each{|x| x.class.should be == Symbol}}
        data.each do |h|
          h.keys.each do |key|
            [:first_name, :last_name, :dogs, :cats, :birds, :fish].should include( key )
          end
          h.size.should <= 6
        end
      end

      context 'with full user_provided_headers' do
        let(:options) { super().merge({user_provided_headers: [:a, :b, :c, :d, :e, :f]}) }

        it 'replaces headers with user_provided_headers' do
          data = SmarterCSV.process("#{fixture_path}/basic.csv", options)
          data.size.should == 5

          SmarterCSV.raw_header.should eq "First Name,Last Name,Dogs,Cats,Birds,Fish\n"
          SmarterCSV.headers.should eq [:a, :b, :c, :d, :e, :f]
        end
      end

      context 'with partial user_provided_headers' do
        let(:options) { super().merge({user_provided_headers: [:a, :b, :c, :d, :e]}) }

        it 'raises an exception if the number of user_provided_headers is incorrect' do
          expect {
            SmarterCSV.process("#{fixture_path}/basic.csv", options)
          }.to raise_error(SmarterCSV::HeaderSizeMismatch)
        end
      end
    end

  end
end