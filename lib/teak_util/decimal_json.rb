# frozen_string_literal: true

require 'bigdecimal'
require 'json'

module TeakUtil
  # Writes BigDecimal as an exact, bare JSON number. ActiveSupport and Oj (compat) both
  # encode a BigDecimal as a quoted string, and Float isn't exact at nine decimal places
  # next to a large integer part, so nothing in here goes through Float.
  #
  #   TeakUtil::DecimalJson.dump({ 'qty' => BigDecimal('0.000000001') })
  #   # => '{"qty":0.000000001}'
  #
  # Whole values become Integers, so 5 and 5.0 sign and serialize identically. Fractional
  # values become a Fractional, which JSON.generate, ActiveSupport's to_json and Oj
  # (compat, use_to_json) all write as plain-notation digits, never "0.123e18" or quoted.
  module DecimalJson
    # A fractional decimal that every JSON encoder in the stack writes as a bare number.
    # `as_json` returns self so ActiveSupport's recursive `as_json` leaves it alone, and
    # `to_json` is what the JSON gem and Oj (compat) call to emit the raw digits.
    # JSON output only: use the BigDecimal (`decimal`) for anything else.
    class Fractional < Numeric
      attr_reader :decimal

      def initialize(decimal)
        super()
        @decimal = decimal
      end

      def to_s(*)
        @decimal.to_s('F')
      end

      def to_json(*)
        to_s
      end

      def as_json(*)
        self
      end
    end

    # Returns a copy of the Hash/Array tree with every BigDecimal replaced by something
    # the encoders write as a bare number. Hash keys and non-BigDecimal values are left
    # alone. Raises ArgumentError for NaN and Infinity, which have no JSON form.
    def self.wire(value)
      case value
      when BigDecimal then wire_decimal(value)
      when Hash then value.transform_values { |v| wire(v) }
      when Array then value.map { |v| wire(v) }
      else value
      end
    end

    # JSON text for the tree, with BigDecimal values written as bare numbers.
    def self.dump(value)
      JSON.generate(wire(value))
    end

    def self.wire_decimal(decimal)
      raise ArgumentError, "Decimal must be finite, got #{decimal}" unless decimal.finite?

      decimal.frac.zero? ? decimal.to_i : Fractional.new(decimal)
    end
    private_class_method :wire_decimal
  end
end
