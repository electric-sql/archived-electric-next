defmodule Electric.IntegrationTest do
  use ExUnit.Case, async: false
  @postgres_port 54323
  @database "electric"

  setup :start_postgres

  setup do
    config =
      PostgresqlUri.parse(
        "postgresql://postgres:password@localhost:#{@postgres_port}/#{@database}"
      )

    {:ok, pool} =
      Postgrex.start_link(config ++ [backoff_min: 500, backoff_max: 600])

    Postgrex.query!(pool, "CREATE TABLE issues (id UUID PRIMARY KEY, title TEXT NOT NULL);", [])
    add_row(pool)

    {:ok, %{pool: pool, db_config: config, db_conn: pool}}
  end

  setup [{Support.ComponentSetup, :with_complete_stack}]

  setup %{router: router} do
    Bandit.start_link(plug: router, port: 2998)
    :ok
  end

  test "postgres disconnect does not disrupt live query", %{pool: pool, registry: registry} do
    assert %{status: 200, headers: %{"x-electric-shape-id" => [shape_id]}} =
             Req.get!("http://localhost:2998/shape/issues?offset=-1")

    Registry.register(registry, shape_id, nil)

    add_row(pool)

    assert_receive {_, :new_changes, _}, 10_000

    assert %{status: 200, body: [_, %{"offset" => offset}, _]} =
             Req.get!("http://localhost:2998/shape/issues?offset=-1")

    assert offset > 0

    task =
      Task.async(fn ->
        Req.get!("http://localhost:2998/shape/issues?offset=#{offset}&live")
      end)

    restart_postgres()

    add_row(pool)

    assert %{status: 200} = Task.await(task) |> IO.inspect()
  end

  defp add_row(pool) do
    Postgrex.query!(pool, "INSERT INTO issues (id, title) VALUES (gen_random_uuid(), '1');", [])
  end

  @docker_compose_file "test/electric/integration_test/docker-compose.yml"
  def start_postgres(context) do
    {_, 0} =
      System.cmd("docker", ["compose", "--file", @docker_compose_file, "up", "-d"],
        stderr_to_stdout: true
      )

    on_exit(fn ->
      {_, 0} =
        System.cmd("docker", ["compose", "--file", @docker_compose_file, "down"],
          stderr_to_stdout: true
        )

      IO.puts("Postgres closed")
    end)

    Process.sleep(2000)

    {:ok, context}
  end

  def restart_postgres do
    {_, 0} =
      System.cmd("docker", ["restart", "electric_test-postgres-1"], stderr_to_stdout: true)
  end
end
