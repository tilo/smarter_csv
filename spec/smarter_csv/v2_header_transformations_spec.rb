# frozen_string_literal: true

fixture_path = 'spec/fixtures'
RSpec.describe SmarterCSV do
  describe 'something .header_transformations_v2' do
    # it 'with dashes in header fields as symbols when using v1 defaults' do
    #   options = {
    #     defaults: 'v1'
    #   }
    #   data = SmarterCSV.process("#{fixture_path}/with_dashes.csv", options)

    #   expect(data.size).to eq 5
    #   expect(data[0][:first_name]).to eq 'Dan'
    #   expect(data[0][:last_name]).to eq 'McAllister'
    # end

    # it 'with dashes in header fields as symbols when using safe defaults' do
    #   options = {
    #     defaults: 'safe'
    #   }
    #   data = SmarterCSV.process("#{fixture_path}/with_dashes.csv", options)

    #   expect(data.size).to eq 5
    #   expect(data[0][:first_name]).to eq 'Dan'
    #   expect(data[0][:last_name]).to eq 'McAllister'
    # end

    # Unit Tests

    context 'when transformation is an invalid type' do
      it 'raises an ArgumentError' do
        header_array = ['header1', 'header2']
        invalid_transformation = 'invalid'
        options = { v2_mode: true, header_transformations: [invalid_transformation] }

        expect { SmarterCSV.header_transformations_v2(header_array, options) }.to raise_error(SmarterCSV::IncorrectOption, "Invalid transformation type: String")
      end
    end

    context 'when transformation is a symbol / pre-defined in SmarterCSV module' do
      it 'applies the predefined :keys_as_strings transformation method' do
        header_array = ['Header1', 'Header2']
        options = { v2_mode: true, header_transformations: [:keys_as_strings] }

        expect(SmarterCSV).to receive(:keys_as_strings).with(header_array, options).and_call_original
        result = SmarterCSV.header_transformations_v2(header_array, options)

        expect(result).to eq(['header1', 'header2'])
      end

      it 'applies the predefined :downcase_headers transformation method' do
        header_array = ['Header1', 'Header2']
        options = { v2_mode: true, header_transformations: [:downcase_headers] }

        expect(SmarterCSV).to receive(:downcase_headers).with(header_array, options).and_call_original
        result = SmarterCSV.header_transformations_v2(header_array, options)

        expect(result).to eq(['header1', 'header2'])
      end

      it 'applies the predefined :keys_as_symbols transformation method' do
        header_array = ['Header1', 'Header2']
        options = { v2_mode: true, header_transformations: [:keys_as_symbols] }

        expect(SmarterCSV).to receive(:keys_as_symbols).with(header_array, options).and_call_original
        result = SmarterCSV.header_transformations_v2(header_array, options)

        expect(result).to eq([:header1, :header2])
      end
    end

    context 'when transformation with arguments is passed-in as a top-level hash' do
      context 'when using a Proc' do
        let(:custom_transformation) do
          Proc.new do |headers, args, _options|
            suffix = args.first
            headers.map { |header| "#{header}_#{suffix}" }
          end
        end

        it 'applies the transformation method with arguments, processed as an array' do
          header_array = ['header1', 'header2']
          options = { v2_mode: true, header_transformations: { custom_transformation => 'arg' } }

          expect(SmarterCSV).to receive(:apply_transformation).with(custom_transformation, header_array, ['arg'], options).and_call_original
          result = SmarterCSV.header_transformations_v2(header_array, options)

          expect(result).to eq(['header1_arg', 'header2_arg'])
        end
      end
    end

    context 'when transformation with arguments is passed-in via hash' do
      context 'when using a Proc' do
        let(:custom_transformation) do
          Proc.new do |headers, args, _options|
            headers.map { |header| "#{header}_#{args}" } # no .first !
          end
        end

        it 'applies the transformation method with arguments, processed as a hash' do
          header_array = ['header1', 'header2']
          options = { v2_mode: true, header_transformations: [{ custom_transformation => 'arg' }] }

          expect(SmarterCSV).to receive(:apply_transformation).with(custom_transformation, header_array, 'arg', options).and_call_original
          result = SmarterCSV.header_transformations_v2(header_array, options)

          expect(result).to eq(['header1_arg', 'header2_arg'])
        end
      end
    end

    context 'when transformation with arguments is passed-in an array' do
      context 'when using a Proc' do
        let(:apply_suffix) do
          Proc.new do |headers, arg, _options|
            suffix = arg.first
            headers.map { |header| "#{header}_#{suffix}" }
          end
        end

        it 'applies the transformation method with array arguments' do
          header_array = ['header1', 'header2']
          options = { v2_mode: true, header_transformations: [[apply_suffix, 'sfx']] }

          expect(SmarterCSV).to receive(:apply_transformation).with(apply_suffix, header_array, ['sfx'], options).and_call_original
          result = SmarterCSV.header_transformations_v2(header_array, options)

          expect(result).to eq(['header1_sfx', 'header2_sfx'])
        end
      end
    end

    context 'when using :key_mapping transformation' do
      let(:header_array) { ['header1', 'header2'] }
      it 'raises an exception if invalid mapping is passed-in' do
        options = { v2_mode: true, header_transformations: [{key_mapping: []}] }

        expect { SmarterCSV.header_transformations_v2(header_array, options) }.to raise_error(SmarterCSV::IncorrectOption, "ERROR: incorrect format for key_mapping! Expecting hash with from -> to mappings")
      end

      it 'applies the transformation method with array arguments' do
        mapping = {'header1' => 'mapped1', 'header2' => 'mapped2'}
        options = { v2_mode: true, header_transformations: [{key_mapping: mapping}] }

        expect(SmarterCSV).to receive(:apply_transformation).with(:key_mapping, header_array, mapping, options).and_call_original

        result = SmarterCSV.header_transformations_v2(header_array, options)

        expect(result).to eq(['mapped1', 'mapped2'])
      end

      it 'can delete a column when mapped to nil, and map other columns' do
        mapping = {'header1' => nil, 'header2' => 'mapped2'}
        options = { v2_mode: true, header_transformations: [{key_mapping: mapping}] }

        expect(SmarterCSV).to receive(:apply_transformation).with(:key_mapping, header_array, mapping, options).and_call_original

        result = SmarterCSV.header_transformations_v2(header_array, options)

        expect(result).to eq([nil, 'mapped2'])
      end

      context 'when mapping only one key' do
        let(:mapping) { {'header2' => 'mapped2'} }
        let(:options) { { v2_mode: true, header_transformations: [{key_mapping: mapping}] } }

        it 'removes unmapped keys' do
          expect(SmarterCSV).to receive(:apply_transformation).with(:key_mapping, header_array, mapping, options).and_call_original

          result = SmarterCSV.header_transformations_v2(header_array, options)

          expect(result).to eq(['header1', 'mapped2'])
        end
      end
    end

    # Functional tests

    context 'using built-in transformations' do
      it 'with dashes in header fields as strings' do
        options = {
          v2_mode: true,
          header_transformations: [:none, :keys_as_strings],
        }
        data = SmarterCSV.process("#{fixture_path}/with_dashes.csv", options)
        expect(data.size).to eq 5
        expect(data[0]['first_name']).to eq 'Dan'
        expect(data[0]['last_name']).to eq 'McAllister'
      end

      it 'no transformations: with dashes in header fields as is' do
        options = {
          v2_mode: true,
          header_transformations: [:none]
        }
        data = SmarterCSV.process("#{fixture_path}/with_dashes.csv", options)
        expect(data.size).to eq 5
        expect(data[0]['First-Name']).to eq 'Dan'
        expect(data[0]['Last-Name']).to eq 'McAllister'
      end

      it 'with dashes in header fields as symbols' do
        options = {
          v2_mode: true,
          header_transformations: [:none, :keys_as_symbols]
        }
        data = SmarterCSV.process("#{fixture_path}/with_dashes.csv", options)

        expect(data.size).to eq 5
        expect(data[0][:first_name]).to eq 'Dan'
        expect(data[0][:last_name]).to eq 'McAllister'
      end

      context "key_mapping" do
        it 'can delete a column with :key_mapping when mapped to nil' do
          mapping = {'Dogs' => :wuff, 'Cats' => :miau}
          options = { v2_mode: true, header_transformations: [{key_mapping: mapping}] }

          data = SmarterCSV.process("#{fixture_path}/with_dashes.csv", options)

          expect(data.size).to eq 5
          expect(data.first.keys).to eq ["First-Name", "Last-Name", :wuff, :miau]
          expect(data[0]["First-Name"]).to eq "Dan"
          expect(data[0]["Last-Name"]).to eq 'McAllister'
          expect(data[0][:wuff]).to eq 2
          expect(data[0][:miau]).to eq 0
        end

        it 'can delete a column with :key_mapping when mapped to nil' do
          mapping = {'Dogs' => nil}
          options = { v2_mode: true, header_transformations: [{key_mapping: mapping}] }

          data = SmarterCSV.process("#{fixture_path}/with_dashes.csv", options)

          expect(data.size).to eq 5
          expect(data.first.keys).to eq ["First-Name", "Last-Name", "Cats"]
          data.each do |hash|
            expect(hash.keys.include?("Dogs")).to eq false
          end
        end
      end
    end

    context 'with provided transformations' do
      # user-provided custom transformation
      let(:camelcase) do
        Proc.new do |headers, _options|
          headers.map do |header|
            header.strip.downcase.gsub(/(\s|-)+/, '_').split('_').map(&:capitalize).join
          end
        end
      end

      it 'applies the custom transformation' do
        options = {
          v2_mode: true,
          header_transformations: [:none, camelcase],
        }
        data = SmarterCSV.process("#{fixture_path}/with_dashes.csv", options)
        expect(data.size).to eq 5
        expect(data[0]['FirstName']).to eq 'Dan'
        expect(data[0]['LastName']).to eq 'McAllister'
      end
    end

    context 'using transformations that have arguments' do
      let(:prefix_proc) do
        Proc.new do |headers, args, _options|
          headers.map { |header| "#{args.first}_#{header}" }
        end
      end

      it 'with dashes in header fields as strings' do
        options = {
          v2_mode: true,
          header_transformations: [:none, [prefix_proc, 'pre']],
        }
        data = SmarterCSV.process("#{fixture_path}/with_dashes.csv", options)

        expect(data.size).to eq 5
        expect(data[0]['pre_First-Name']).to eq 'Dan'
        expect(data[0]['pre_Last-Name']).to eq 'McAllister'
      end
    end
  end
end
