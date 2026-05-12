# frozen_string_literal: true

module Templates
  module TemplateInterpolator
    PLACEHOLDER = /\{\{(\w+)\}\}/

    def self.interpolate(string, context)
      missing = []
      result = string.to_s.gsub(PLACEHOLDER) do
        key = Regexp.last_match(1).to_sym
        if context.key?(key)
          context[key].to_s
        else
          missing << key.to_s
          ""
        end
      end
      { result: result, missing: missing.uniq }
    end
  end
end
