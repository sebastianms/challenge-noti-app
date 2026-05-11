# frozen_string_literal: true

require "rails_helper"

RSpec.describe NotificationBlacklist, "schema" do
  describe "CHECK blacklist_scope_target_chk" do
    it "rechaza scope=global con target presente" do
      expect {
        described_class.connection.execute(<<~SQL)
          INSERT INTO notification_blacklist (recipient_canonical, scope, target, source)
          VALUES ('a@x.com', 'global', 'birthday', 'manual')
        SQL
      }.to raise_error(ActiveRecord::StatementInvalid, /blacklist_scope_target_chk/)
    end

    it "rechaza scope=type con target NULL" do
      expect {
        described_class.connection.execute(<<~SQL)
          INSERT INTO notification_blacklist (recipient_canonical, scope, target, source)
          VALUES ('a@x.com', 'type', NULL, 'manual')
        SQL
      }.to raise_error(ActiveRecord::StatementInvalid, /blacklist_scope_target_chk/)
    end

    it "rechaza scope=channel con target NULL" do
      expect {
        described_class.connection.execute(<<~SQL)
          INSERT INTO notification_blacklist (recipient_canonical, scope, target, source)
          VALUES ('a@x.com', 'channel', NULL, 'manual')
        SQL
      }.to raise_error(ActiveRecord::StatementInvalid, /blacklist_scope_target_chk/)
    end
  end

  describe "CHECK blacklist_scope_values_chk" do
    it "rechaza scope desconocido" do
      expect {
        described_class.connection.execute(<<~SQL)
          INSERT INTO notification_blacklist (recipient_canonical, scope, target, source)
          VALUES ('a@x.com', 'unknown_scope', 'x', 'manual')
        SQL
      }.to raise_error(ActiveRecord::StatementInvalid, /blacklist_scope_(values|target)_chk/)
    end
  end

  describe "CHECK blacklist_source_values_chk" do
    it "rechaza source desconocido" do
      expect {
        described_class.connection.execute(<<~SQL)
          INSERT INTO notification_blacklist (recipient_canonical, scope, source)
          VALUES ('a@x.com', 'global', 'unknown_source')
        SQL
      }.to raise_error(ActiveRecord::StatementInvalid, /blacklist_source_values_chk/)
    end
  end

  describe "UNIQUE idx_blacklist_unique con NULLS NOT DISTINCT" do
    it "rechaza duplicado (recipient, scope, target) con target presente" do
      described_class.create!(recipient_canonical: "dup@x.com", scope: "channel", target: "email", source: "manual")

      expect {
        described_class.create!(recipient_canonical: "dup@x.com", scope: "channel", target: "email", source: "admin_ui")
      }.to raise_error(ActiveRecord::RecordNotUnique, /idx_blacklist_unique/)
    end

    it "rechaza duplicado (recipient, global, NULL) — NULLS NOT DISTINCT" do
      described_class.create!(recipient_canonical: "dup2@x.com", scope: "global", source: "manual")

      expect {
        described_class.create!(recipient_canonical: "dup2@x.com", scope: "global", source: "admin_ui")
      }.to raise_error(ActiveRecord::RecordNotUnique, /idx_blacklist_unique/)
    end

    it "permite filas distintas en scope/target para el mismo recipient" do
      described_class.create!(recipient_canonical: "mix@x.com", scope: "global", source: "manual")
      described_class.create!(recipient_canonical: "mix@x.com", scope: "type", target: "marketing", source: "manual")
      described_class.create!(recipient_canonical: "mix@x.com", scope: "channel", target: "email", source: "manual")

      expect(described_class.where(recipient_canonical: "mix@x.com").count).to eq(3)
    end
  end
end
