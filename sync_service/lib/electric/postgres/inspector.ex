defmodule Electric.Postgres.Inspector do
  @doc """
  Load table information (refs) from the database
  """
  def load_table_info(conn, {namespace, tbl}) do
    query = """
    SELECT
      pg_class.oid,
      attname,
      atttypid,
      atttypmod,
      typname,
      format_type(pg_attribute.atttypid, pg_attribute.atttypmod) AS formatted_type,
      array_position(indkey, attnum) as pk_position
    FROM pg_class
    JOIN pg_namespace ON relnamespace = pg_namespace.oid
    JOIN pg_attribute ON attrelid = pg_class.oid AND attnum >= 0
    JOIN pg_type ON atttypid = pg_type.oid
    JOIN pg_index ON indrelid = pg_class.oid AND indisprimary
    WHERE relname = $1 AND nspname = $2
    ORDER BY pg_class.oid, attnum
    """

    result = Postgrex.query!(conn, query, [tbl, namespace])

    Enum.map(result.rows, fn row -> Enum.zip(result.columns, row) |> Map.new() end)
  end
end
