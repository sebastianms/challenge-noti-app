# frozen_string_literal: true

class PartitionManager
  SAFETY_MIN_MONTHS    = 3
  IDENTIFIER_PATTERN   = /\A[a-z_][a-z0-9_]{0,62}\z/
  InvalidTableName     = Class.new(ArgumentError)

  def initialize(table:, retention_months:)
    raise InvalidTableName, "invalid table name: #{table.inspect}" unless IDENTIFIER_PATTERN.match?(table.to_s)

    @table            = table.to_s
    @retention_months = retention_months.to_i
  end

  def rotate(now: Time.current)
    create_next_month_partition(now: now)
    drop_old_partitions(now: now)
  end

  def create_next_month_partition(now: Time.current)
    target    = now.utc.beginning_of_month.next_month
    name      = partition_name(target)
    from_date = target.strftime("%Y-%m-%d")
    to_date   = target.next_month.strftime("%Y-%m-%d")

    quoted_parent = connection.quote_table_name(@table)
    quoted_child  = connection.quote_table_name(name)
    quoted_from   = connection.quote(from_date)
    quoted_to     = connection.quote(to_date)

    connection.execute(
      "CREATE TABLE IF NOT EXISTS #{quoted_child} " \
      "PARTITION OF #{quoted_parent} " \
      "FOR VALUES FROM (#{quoted_from}) TO (#{quoted_to})"
    )
    name
  end

  def drop_old_partitions(now: Time.current)
    if @retention_months < SAFETY_MIN_MONTHS
      Rails.logger.warn("[PartitionManager] retention_months=#{@retention_months} below safety minimum (#{SAFETY_MIN_MONTHS}); skipping drop")
      return []
    end

    cutoff  = now.utc.beginning_of_month - @retention_months.months
    dropped = []

    partitions.each do |name, range_from|
      next unless range_from < cutoff
      next unless IDENTIFIER_PATTERN.match?(name)

      connection.execute("DROP TABLE IF EXISTS #{connection.quote_table_name(name)}")
      dropped << name
    end
    dropped
  end

  private

  def partition_name(time)
    "#{@table}_#{time.strftime('%Y_%m')}"
  end

  def partitions
    rows = connection.exec_query(<<~SQL, "PartitionManager.list", [ @table ])
      SELECT child.relname AS name,
             pg_get_expr(child.relpartbound, child.oid) AS bound
      FROM pg_inherits
      JOIN pg_class parent ON pg_inherits.inhparent = parent.oid
      JOIN pg_class child  ON pg_inherits.inhrelid  = child.oid
      WHERE parent.relname = $1
    SQL

    rows.filter_map do |row|
      from = parse_range_from(row["bound"])
      from ? [ row["name"], from ] : nil
    end
  end

  def parse_range_from(bound_expr)
    match = bound_expr&.match(/FROM \('([^']+)'\)/)
    match && Time.zone.parse(match[1])
  end

  def connection
    ActiveRecord::Base.connection
  end
end
