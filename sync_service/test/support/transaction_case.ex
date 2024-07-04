defmodule Support.TransactionCase do
  @moduledoc """
  Special test case that starts a DB connection, and runs entire test in
  a single Postgrex transaction, rolling it back completely after the test
  has ended.

  Exposes a context variable `conn` to run queries over.
  """
  use ExUnit.CaseTemplate

  setup_all do
    database_config = Application.fetch_env!(:electric, :database_config)

    pool =
      start_supervised!({Postgrex, database_config ++ [backoff_type: :stop, max_restarts: 0]})

    {:ok, %{pool: pool}}
  end

  setup %{pool: pool} do
    parent = self()

    {:ok, task} =
      Task.start(fn ->
        Postgrex.transaction(
          pool,
          fn conn ->
            send(parent, {:conn_handover, conn})

            exit_parent =
              receive do
                {:done, exit_parent} -> exit_parent
              end

            Postgrex.rollback(conn, {:complete, exit_parent})
          end,
          timeout: :infinity
        )
        |> case do
          {:error, {:complete, target}} ->
            send(target, :transaction_complete)

          {:error, _} ->
            receive do
              {:done, target} -> send(target, :transaction_complete)
            end
        end
      end)

    conn =
      receive do
        {:conn_handover, conn} -> conn
      end

    on_exit(fn ->
      send(task, {:done, self()})

      receive do
        :transaction_complete -> :ok
      after
        5000 -> :ok
      end
    end)

    {:ok, %{conn: conn}}
  end
end
