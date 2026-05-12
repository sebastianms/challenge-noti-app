# frozen_string_literal: true

module Admin
  module RulesHelper
    def diff_row(before, after, key)
      b = before&.dig(key)
      a = after&.dig(key)
      { key: key, before: b, after: a, changed: b != a }
    end
  end
end
