# frozen_string_literal: true

class RecipientNormalizer
  MAX_LENGTH = 320

  def self.normalize(raw)
    new(raw).normalize
  end

  def initialize(raw)
    @raw = raw
  end

  def normalize
    validate!
    canonical = @raw.strip.downcase
    type = canonical.include?("@") ? :email : :user_id
    { type: type, canonical: canonical }
  end

  private

  def validate!
    raise ArgumentError, "recipient is blank" if @raw.nil? || @raw.strip.empty?
    raise ArgumentError, "recipient contains invalid characters" if @raw.include?("\n") || @raw.include?("\r")
    raise ArgumentError, "recipient exceeds #{MAX_LENGTH} characters" if @raw.strip.length > MAX_LENGTH
  end
end
