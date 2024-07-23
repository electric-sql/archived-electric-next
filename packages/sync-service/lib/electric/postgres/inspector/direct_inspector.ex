defmodule Electric.Postgres.Inspector.DirectInspector do
  alias Electric.Postgres.PgType
  @behaviour Electric.Postgres.Inspector

  @doc """
  Load table information (refs) from the database
  """
  def load_table_info({namespace, tbl}, conn) do
    query = """
    SELECT
      attname as name,
      (atttypid, atttypmod) as type_id,
      typname as type,
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

    if Enum.empty?(result.rows) do
      :table_not_found
    else
      columns = Enum.map(result.columns, &String.to_atom/1)
      rows = Enum.map(result.rows, fn row -> Enum.zip(columns, row) |> Map.new() end)
      {:ok, rows}
    end
  end

  @doc """
  List all types in the database
  """
  def list_types!(conn) do
    query = """
    SELECT
      nspname,
      t.typname,
      t.oid,
      t.typarray,
      t.typelem,
      t.typlen,
      t.typtype,
      a.oid IS NOT NULL as is_array
    FROM pg_type t
    JOIN pg_namespace ON pg_namespace.oid = t.typnamespace
    LEFT JOIN pg_type a ON t.oid = a.typarray
    WHERE
      t.typtype = ANY($1::char[])
    ORDER BY t.oid
    """

    types = Enum.map([:BASE, :DOMAIN, :ENUM], &PgType.encode_kind/1)

    %{rows: rows} = Postgrex.query!(conn, query, [types])

    Enum.map(rows, &PgType.from_list/1)
  end
end
