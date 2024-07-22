defmodule M do
  def prepare(conn) do
    Postgrex.query!(
      conn,
      """
      CREATE TABLE IF NOT EXISTS items2 (
        id UUID PRIMARY KEY,
        val1 TEXT,
        val2 TEXT,
        index int
      )
      """,
      []
    )

    Postgrex.query!(
      conn,
      """
      ALTER TABLE items2 REPLICA IDENTITY FULL
      """,
      []
    )

    Postgrex.query!(
      conn,
      """
      ALTER PUBLICATION electric_publication ADD TABLE items2
      """,
      []
    )
  end

  def insert(conn) do
    val1 =
      Stream.repeatedly(fn -> :rand.uniform(125 - 32) + 32 end)
      |> Enum.take(4000)

    val2 = Enum.shuffle(val1)

    Postgrex.query!(
      conn,
      """
      INSERT INTO
        items2 (id, val1, val2)
      VALUES
        (gen_random_uuid(), $1, $2)
      """,
      [List.to_string(val1), List.to_string(val2)]
    )
  end

  def update(conn, id, kw) do
    {:ok, uuid} = Ecto.UUID.dump(id)

    {assignments, vals} =
      kw
      |> Stream.with_index(2)
      |> Enum.map(fn {{k, v}, i} ->
        {"#{k} = $#{i}", v}
      end)
      |> Enum.unzip()

    vals =
      Enum.map(vals, fn
        :small ->
          Stream.repeatedly(fn -> :rand.uniform(125 - 32) + 32 end)
          |> Enum.take(100)
          |> List.to_string()

        :large ->
          Stream.repeatedly(fn -> :rand.uniform(125 - 32) + 32 end)
          |> Enum.take(4000)
          |> List.to_string()

        other ->
          other
      end)

    update_str = Enum.join(assignments, ", ")

    Postgrex.query!(
      conn,
      """
      UPDATE
        items2
      SET
        #{update_str}
      WHERE
        id = $1
      """,
      [uuid | vals]
    )
  end
end
