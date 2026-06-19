# frozen_string_literal: true

require 'spec_helper'
require 'bigdecimal'

# Numeric conversion must be byte-identical across the C path (Eisel-Lemire fast path,
# strtod fallback, BigDecimal for high precision) and the Ruby path, for every value of
# the decimal_precision option:
#
#   :float      -> always Float (correctly-rounded; == String#to_f)
#   :bigdecimal -> always BigDecimal (== BigDecimal(str))
#   :auto       -> Float unless the value carries more than 16 significant digits,
#                  then BigDecimal (no precision loss)
#
# Integers stay Integer in every mode. Values that are not numbers (a bare ".5" or "5.",
# which the shared grammar rejects) stay String. Every case runs on both paths via
# [true, false] so the C and Ruby results are proven identical.

# Decimals with <= 16 significant digits: Float in :auto and :float.
LOW_PRECISION_DECIMALS = %w[3.14 0.1 100.0 1399999.99 -2.5 1.5e10 1.5e-5 6.022e23 1e10].freeze

# Decimals with > 16 significant digits: BigDecimal in :auto, Float in :float.
HIGH_PRECISION_DECIMALS = %w[
  0.123456789012345678
  3.14159265358979312
  1234567890123456789.5
  1.7976931348623157e10
].freeze

[true, false].each do |acceleration|
  describe "numeric conversion with#{acceleration ? ' C-' : 'out '}acceleration" do
    def parse(value, **opts)
      SmarterCSV.process(StringIO.new("a,b\n#{value},x\n"), **opts)[0][:a]
    end

    describe 'decimal_precision: :float' do
      (LOW_PRECISION_DECIMALS + HIGH_PRECISION_DECIMALS).each do |str|
        it "parses #{str} as a Float equal to String#to_f" do
          v = parse(str, acceleration: acceleration, decimal_precision: :float)
          expect(v).to be_a(Float)
          expect(v).to eql(str.to_f)
        end
      end
    end

    describe 'decimal_precision: :bigdecimal' do
      (LOW_PRECISION_DECIMALS + HIGH_PRECISION_DECIMALS).each do |str|
        it "parses #{str} as a BigDecimal equal to BigDecimal(str)" do
          v = parse(str, acceleration: acceleration, decimal_precision: :bigdecimal)
          expect(v).to be_a(BigDecimal)
          expect(v).to eq(BigDecimal(str))
        end
      end
    end

    describe 'decimal_precision: :auto (default)' do
      LOW_PRECISION_DECIMALS.each do |str|
        it "parses #{str} (<=16 sig digits) as a Float" do
          v = parse(str, acceleration: acceleration, decimal_precision: :auto)
          expect(v).to be_a(Float)
          expect(v).to eql(str.to_f)
        end
      end

      HIGH_PRECISION_DECIMALS.each do |str|
        it "parses #{str} (>16 sig digits) as a BigDecimal with no precision loss" do
          v = parse(str, acceleration: acceleration, decimal_precision: :auto)
          expect(v).to be_a(BigDecimal)
          expect(v).to eq(BigDecimal(str))
        end
      end

      it "is the default (no option given)" do
        v = parse('0.123456789012345678', acceleration: acceleration)
        expect(v).to be_a(BigDecimal)
      end
    end

    describe 'integers stay Integer in every mode' do
      %i[float auto bigdecimal].each do |mode|
        it "parses 42 as Integer under #{mode}" do
          expect(parse('42', acceleration: acceleration, decimal_precision: mode)).to eql(42)
        end
      end
    end

    describe 'non-numbers stay String (shared grammar rejects them)' do
      ['.5', '5.', '1e10x', 'abc', '1_000'].each do |str|
        it "keeps #{str.inspect} as a String" do
          expect(parse(str, acceleration: acceleration)).to eq(str)
        end
      end
    end
  end
end

# The Eisel-Lemire fast path covers mantissas up to 19 significant digits (any exact
# uint64). These are decimal_precision: :float (in :auto they'd be BigDecimal, >16 sig).
# Each must be correctly rounded — bit-for-bit equal to String#to_f — on BOTH paths,
# including round-to-even tie shapes (mantissa ending in 5) that a weaker algorithm misrounds.
EISEL_LEMIRE_18_19_DIGIT = %w[
  1.23456789012345678
  1.234567890123456789
  9.999999999999999999
  1234567890123456.78
  12345678901234567.8
  0.1234567890123456789
  1.000000000000000005
  1.500000000000000005
  2.234567890123456785
  9.234567890123456785
  1234567890123456789e-5
].freeze

describe 'Eisel-Lemire fast path: 18-19 significant digits, decimal_precision: :float' do
  [true, false].each do |acceleration|
    EISEL_LEMIRE_18_19_DIGIT.each do |str|
      it "correctly rounds #{str} (#{acceleration ? 'C' : 'Ruby'} path)" do
        csv = "a,b\n#{str},x\n"
        v = SmarterCSV.process(StringIO.new(csv), acceleration: acceleration, decimal_precision: :float)[0][:a]
        expect(v).to be_a(Float)
        expect(v).to eql(str.to_f)
      end
    end
  end
end

# Explicit C-vs-Ruby parity sweep across all modes — any divergence trips here.
describe 'numeric conversion: C and Ruby paths agree' do
  samples = LOW_PRECISION_DECIMALS + HIGH_PRECISION_DECIMALS +
            %w[42 -7 0 .5 5. 1_000 abc]
  %i[float auto bigdecimal].each do |mode|
    samples.each do |str|
      it "#{str.inspect} parses identically under #{mode}" do
        csv = "a,b\n#{str},x\n"
        c    = SmarterCSV.process(StringIO.new(csv), acceleration: true,  decimal_precision: mode)
        ruby = SmarterCSV.process(StringIO.new(csv), acceleration: false, decimal_precision: mode)
        expect(c[0][:a].class).to eq(ruby[0][:a].class)
        expect(c).to eq(ruby)
      end
    end
  end
end
