defmodule Electric.Shapes.QueryingTest do
  use Support.TransactionCase, async: true

  alias Electric.Shapes.Shape
  alias Electric.Shapes.Querying

  test "should give information about the table and the result stream", %{conn: conn} do
    Postgrex.query!(
      conn,
      """
      CREATE TABLE items (
        id INTEGER PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
        value INTEGER
      )
      """,
      []
    )

    Postgrex.query!(conn, "INSERT INTO items (value) VALUES (1), (2), (3), (4), (5)", [])

    assert {query_info, stream} = Querying.stream_initial_data(conn, Shape.new!("items", []))

    assert %{columns: ["id", "value"]} = query_info
    assert [[_, 1], [_, 2], [_, 3], [_, 4], [_, 5]] = Enum.to_list(stream)
  end
end