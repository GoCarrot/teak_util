# frozen_string_literal: true

require "bigdecimal"
require "open3"
require "json"
require "active_support"
require "active_support/json"
require "oj"

RSpec.describe TeakUtil::DecimalJson do
  def bd(str) = BigDecimal(str)

  # Every encoder the services use must write the same bytes.
  encoders = {
    "JSON.generate" => ->(obj) { JSON.generate(obj) },
    "ActiveSupport to_json" => ->(obj) { obj.to_json },
    "ActiveSupport::JSON.encode" => ->(obj) { ActiveSupport::JSON.encode(obj) },
    "Oj compat use_to_json" => ->(obj) { Oj.dump(obj, mode: :compat, use_to_json: true) }
  }

  encoders.each do |name, encoder|
    describe "through #{name}" do
      def encode_wired(encoder, tree) = encoder.call(described_class.wire(tree))

      {
        "a large fraction" => ["123456789012345678.123456789", "123456789012345678.123456789"],
        "a tiny fraction" => ["0.000000001", "0.000000001"],
        "a small fraction that BigDecimal prints with an exponent" => ["0.00000000000000000001", "0.00000000000000000001"],
        "a fraction" => ["1.5", "1.5"],
        "a negative fraction" => ["-2.25", "-2.25"],
        "a whole value with a fractional zero" => ["5.0", "5"],
        "a whole value" => ["100", "100"],
        "a large whole value" => ["1000000000000000000000000000000", "1000000000000000000000000000000"],
        "zero" => ["0", "0"],
        "negative zero" => ["-0", "0"]
      }.each do |desc, (input, expected)|
        it "writes #{desc} as a bare number" do
          expect(encode_wired(encoder, { "q" => bd(input) })).to eq(%({"q":#{expected}}))
        end
      end

      it "writes decimals nested in hashes and arrays" do
        tree = { a: [bd("1.5"), { b: bd("2.25") }, 3], "c" => { d: [bd("0.1")] } }
        expect(encode_wired(encoder, tree)).to eq('{"a":[1.5,{"b":2.25},3],"c":{"d":[0.1]}}')
      end

      it "writes a bare top-level decimal" do
        expect(encode_wired(encoder, bd("1.5"))).to eq("1.5")
      end

      it "leaves everything else as it dumps today" do
        tree = { "i" => 1, "f" => 2.5, "s" => "x", "n" => nil, "t" => true, "sym" => :y, "a" => [1, "z"] }
        expect(encode_wired(encoder, tree)).to eq(encoder.call(tree))
      end
    end
  end

  describe ".wire" do
    it "turns whole decimals into integers" do
      expect(described_class.wire(bd("5.0"))).to eql(5)
    end

    it "does not touch hash keys" do
      expect(described_class.wire({ bd("1.5") => 1 }).keys).to eq([bd("1.5")])
    end

    it "does not mutate its input" do
      tree = { "a" => [bd("1.5")], "b" => bd("2") }
      described_class.wire(tree)
      expect(tree).to eq({ "a" => [bd("1.5")], "b" => bd("2") })
    end

    it "returns non-container, non-decimal values unchanged" do
      obj = Object.new
      expect(described_class.wire(obj)).to equal(obj)
      expect(described_class.wire("str")).to eq("str")
      expect(described_class.wire(nil)).to be_nil
    end

    it "keeps the exact value on the wrapper" do
      wrapped = described_class.wire(bd("0.000000001"))
      expect(wrapped.decimal).to eq(bd("0.000000001"))
      expect(wrapped.to_s).to eq("0.000000001")
    end

    [BigDecimal("NaN"), BigDecimal("Infinity"), BigDecimal("-Infinity")].each do |bad|
      it "raises on #{bad}" do
        expect { described_class.wire(bad) }.to raise_error(ArgumentError, /finite/)
        expect { described_class.wire({ "a" => [bad] }) }.to raise_error(ArgumentError, /finite/)
      end
    end
  end

  describe ".dump" do
    it "wires then JSON.generates" do
      expect(described_class.dump({ "a" => bd("123456789012345678.123456789"), "b" => bd("3.0") }))
        .to eq('{"a":123456789012345678.123456789,"b":3}')
    end

    it "raises on non-finite decimals" do
      expect { described_class.dump({ "a" => bd("NaN") }) }.to raise_error(ArgumentError, /finite/)
    end
  end

  # ActiveSupport redefines BigDecimal#to_s to default to plain notation, which would
  # hide a missing to_s('F') in every example above. Check in a process without it.
  it "writes plain notation without ActiveSupport loaded" do
    script = <<~RUBY
      require "teak_util"
      raise "ActiveSupport leaked in" if defined?(ActiveSupport)
      print TeakUtil::DecimalJson.dump({ "a" => BigDecimal("123456789012345678.123456789"), "b" => BigDecimal("0.000000001") })
    RUBY
    lib = File.expand_path("../lib", __dir__)
    out, status = Open3.capture2e(RbConfig.ruby, "-I", lib, "-e", script)
    expect(status).to be_success, out
    expect(out).to eq('{"a":123456789012345678.123456789,"b":0.000000001}')
  end
end
