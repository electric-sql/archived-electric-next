defmodule Support.DbSetup do
  import ExUnit.Callbacks

  alias Electric.Client.Util

  def with_unique_table(_ctx) do
    base_config = Application.fetch_env!(:electric_client, :database_config)
    extra_opts = [backoff_type: :stop, max_restarts: 0]

    {:ok, utility_pool} = Postgrex.start_link(base_config ++ extra_opts)

    Process.unlink(utility_pool)

    tablename = "client_items_#{Util.generate_id(6)}"

    Postgrex.query!(
      utility_pool,
      """
        CREATE TABLE \"#{tablename}\" (
          id uuid primary key,
          title text
        );
      """,
      []
    )

    on_exit(fn ->
      Process.link(utility_pool)
      Postgrex.query!(utility_pool, "DROP TABLE \"#{tablename}\"", [])
      GenServer.stop(utility_pool)
    end)

    {:ok, pool} = Postgrex.start_link(base_config ++ extra_opts)
    {:ok, %{utility_pool: utility_pool, pool: pool, db_conn: pool, tablename: tablename}}
  end

  def insert_item(db_conn, tablename) do
    id = UUID.uuid4()

    %Postgrex.Result{num_rows: 1} =
      Postgrex.query!(
        db_conn,
        """
          INSERT INTO \"#{tablename}\" (
              id,
              title
            )
            VALUES (
              $1,
              'Some title'
            );
        """,
        [UUID.string_to_binary!(id)]
      )

    {:ok, id}
  end
end
