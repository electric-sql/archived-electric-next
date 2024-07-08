defmodule Electric.Shapes.Querying do
  alias Electric.Shapes.Shape

  @type row :: [term()]

  @spec stream_initial_data(DBConnection.t(), Shape.t()) ::
          {Postgrex.Query.t(), Enumerable.t(row())}
  def stream_initial_data(conn, %Shape{} = shape) do
    {schema, table} = shape.root_table

    query =
      Postgrex.prepare!(
        conn,
        ~s|"#{schema}"."#{table}"|,
        ~s|SELECT * FROM "#{schema}"."#{table}" WHERE #{shape.where.query}|
      )

    stream =
      Postgrex.stream(conn, query, [])
      |> Stream.flat_map(& &1.rows)

    {query, stream}
  end
end
