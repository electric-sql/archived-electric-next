defmodule Electric.SchemaTest do
  use Support.TransactionCase, async: true

  alias Electric.Schema
  alias Electric.Postgres.Inspector.DirectInspector

  @postgres_types [
    "SMALLINT",
    "INTEGER",
    "BIGINT",
    "NUMERIC",
    "NUMERIC(5,0)",
    "REAL",
    "DOUBLE PRECISION",
    "CHARACTER VARYING(123)"
  ]

  describe "from_column_info/1" do
    for postgres_type <- @postgres_types do
      test "gets the type for #{postgres_type}", %{db_conn: conn} do
        Postgrex.query!(
          conn,
          """
          CREATE TABLE items (
            id INTEGER PRIMARY KEY,
            value #{unquote(postgres_type)})
          """,
          []
        )

        {:ok, column_info} = DirectInspector.load_column_info({"public", "items"}, conn)

        assert %{"value" => unquote(postgres_type)} = Schema.from_column_info(column_info)
      end
    end
  end
end
