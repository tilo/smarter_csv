# frozen_string_literal: true

require 'spec_helper'

describe 'options processing' do
  SmarterCSV::OBSOLETE_OPTIONS.each do |key, value|
    it "raises an error if option #{key} is given" do
      options = {key => value}
      expect do
        SmarterCSV.process_options(options)
      end.to raise_exception(SmarterCSV::ObsoleteOptions)
    end
  end

  it 'it has the correct default options, when no input is given' do
    options = {}
    generated_options = SmarterCSV.process_options(options)
    generated_options.should eq SmarterCSV::DEFAULT_OPTIONS.merge(SmarterCSV::BASE_TRANSFORMATIONS)
  end

  it 'lets the user clear out all default options' do
    options = {defaults: :none}
    generated_options = SmarterCSV.process_options(options)
    generated_options.should eq options
  end

  it 'it has the correct v1 default options when requested' do
    options = {defaults: :v1}
    generated_options = SmarterCSV.process_options(options)
    generated_options.should eq SmarterCSV::DEFAULT_OPTIONS.merge(SmarterCSV::V1_TRANSFORMATIONS).merge(options)
  end

  it 'appends header_transformations to the default ones' do
    options = {header_transformations: [:a, :b, :c]}
    expected = SmarterCSV::DEFAULT_OPTIONS.merge(SmarterCSV::BASE_TRANSFORMATIONS)
    expected[:header_transformations] += [:a, :b, :c]
    generated_options = SmarterCSV.process_options(options)
    generated_options.should eq expected
  end

  it 'appends header_validations to the default ones' do
    options = {header_validations: [:a, :b, :c]}
    expected = SmarterCSV::DEFAULT_OPTIONS.merge(SmarterCSV::BASE_TRANSFORMATIONS)
    expected[:header_validations] += [:a, :b, :c]
    generated_options = SmarterCSV.process_options(options)
    generated_options.should eq expected
  end

  it 'appends data_transformations to the default ones' do
    options = {data_transformations: [:a, :b, :c]}
    expected = SmarterCSV::DEFAULT_OPTIONS.merge(SmarterCSV::BASE_TRANSFORMATIONS)
    expected[:data_transformations] += [:a, :b, :c]
    generated_options = SmarterCSV.process_options(options)
    generated_options.should eq expected
  end

  it 'appends data_validations to the default ones' do
    options = {data_validations: [:a, :b, :c]}
    expected = SmarterCSV::DEFAULT_OPTIONS.merge(SmarterCSV::BASE_TRANSFORMATIONS)
    expected[:data_validations] += [:a, :b, :c]
    generated_options = SmarterCSV.process_options(options)
    generated_options.should eq expected
  end

  it 'appends hash_transformations to the default ones' do
    options = {hash_transformations: [:a, :b, :c]}
    expected = SmarterCSV::DEFAULT_OPTIONS.merge(SmarterCSV::BASE_TRANSFORMATIONS)
    expected[:hash_transformations] += [:a, :b, :c]
    generated_options = SmarterCSV.process_options(options)
    generated_options.should eq expected
  end

  it 'appends hash_validations to the default ones' do
    options = {hash_validations: [:a, :b, :c]}
    expected = SmarterCSV::DEFAULT_OPTIONS.merge(SmarterCSV::BASE_TRANSFORMATIONS)
    expected[:hash_validations] += [:a, :b, :c]
    generated_options = SmarterCSV.process_options(options)
    generated_options.should eq expected
  end

  it 'lets the user clear all default validations/transformations' do
    options = { defaults: :no_procs }
    generated_options = SmarterCSV.process_options(options)
    generated_options.should eq SmarterCSV::DEFAULT_OPTIONS.merge(options)
  end

  it 'lets the user clear out header_transformations' do
    options = {header_transformations: :none}
    expected = SmarterCSV::DEFAULT_OPTIONS.merge(SmarterCSV::BASE_TRANSFORMATIONS)
    expected[:header_transformations] = []
    generated_options = SmarterCSV.process_options(options)
    generated_options.should eq expected
  end

  it 'lets the user clear out header_validations' do
    options = {header_validations: :none}
    expected = SmarterCSV::DEFAULT_OPTIONS.merge(SmarterCSV::BASE_TRANSFORMATIONS)
    expected[:header_validations] = []
    generated_options = SmarterCSV.process_options(options)
    generated_options.should eq expected
  end

  it 'lets the user clear out data_transformations' do
    options = {data_transformations: :none}
    expected = SmarterCSV::DEFAULT_OPTIONS.merge(SmarterCSV::BASE_TRANSFORMATIONS)
    expected[:data_transformations] = []
    generated_options = SmarterCSV.process_options(options)
    generated_options.should eq expected
  end

  it 'lets the user clear out data_transformations' do
    options = {data_transformations: :none}
    expected = SmarterCSV::DEFAULT_OPTIONS.merge(SmarterCSV::BASE_TRANSFORMATIONS)
    expected[:data_transformations] = []
    generated_options = SmarterCSV.process_options(options)
    generated_options.should eq expected
  end

  it 'lets the user clear out hash_transformations' do
    options = {hash_transformations: :none}
    expected = SmarterCSV::DEFAULT_OPTIONS.merge(SmarterCSV::BASE_TRANSFORMATIONS)
    expected[:hash_transformations] = []
    generated_options = SmarterCSV.process_options(options)
    generated_options.should eq expected
  end

  it 'lets the user clear out hash_transformations' do
    options = {hash_transformations: :none}
    expected = SmarterCSV::DEFAULT_OPTIONS.merge(SmarterCSV::BASE_TRANSFORMATIONS)
    expected[:hash_transformations] = []
    generated_options = SmarterCSV.process_options(options)
    generated_options.should eq expected
  end

  it 'lets the user clear out header_transformations and define their own' do
    options = {header_transformations: [:none, :a, :b, :c]}
    expected = SmarterCSV::DEFAULT_OPTIONS.merge(SmarterCSV::BASE_TRANSFORMATIONS)
    expected[:header_transformations] = [:a, :b, :c]
    generated_options = SmarterCSV.process_options(options)
    generated_options.should eq expected
  end

  it 'lets the user clear out header_validations and define their own' do
    options = {header_validations: [:none, :a, :b, :c]}
    expected = SmarterCSV::DEFAULT_OPTIONS.merge(SmarterCSV::BASE_TRANSFORMATIONS)
    expected[:header_validations] = [:a, :b, :c]
    generated_options = SmarterCSV.process_options(options)
    generated_options.should eq expected
  end

  it 'lets the user clear out data_transformations and define their own' do
    options = {hash_transformations: [:none, :a, :b, :c]}
    expected = SmarterCSV::DEFAULT_OPTIONS.merge(SmarterCSV::BASE_TRANSFORMATIONS)
    expected[:hash_transformations] = [:a, :b, :c]
    generated_options = SmarterCSV.process_options(options)
    generated_options.should eq expected
  end

  it 'lets the user clear out data_validations and define their own' do
    options = {data_validations: [:none, :a, :b, :c]}
    expected = SmarterCSV::DEFAULT_OPTIONS.merge(SmarterCSV::BASE_TRANSFORMATIONS)
    expected[:data_validations] = [:a, :b, :c]
    generated_options = SmarterCSV.process_options(options)
    generated_options.should eq expected
  end

  it 'lets the user clear out hash_transformations and define their own' do
    options = {hash_transformations: [:none, :a, :b, :c]}
    expected = SmarterCSV::DEFAULT_OPTIONS.merge(SmarterCSV::BASE_TRANSFORMATIONS)
    expected[:hash_transformations] = [:a, :b, :c]
    generated_options = SmarterCSV.process_options(options)
    generated_options.should eq expected
  end

  it 'lets the user clear out hash_validations and define their own' do
    options = {hash_validations: [:none, :a, :b, :c]}
    expected = SmarterCSV::DEFAULT_OPTIONS.merge(SmarterCSV::BASE_TRANSFORMATIONS)
    expected[:hash_validations] = [:a, :b, :c]
    generated_options = SmarterCSV.process_options(options)
    generated_options.should eq expected
  end

  it 'corrects :invalid_byte_sequence if nil is given' do
    generated_options = SmarterCSV.process_options(invalid_byte_sequence: nil)
    generated_options[:invalid_byte_sequence].should eq ''
  end
end
