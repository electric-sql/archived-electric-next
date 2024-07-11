defmodule Electric.Postgres.ReplicationClientTest do
  use ExUnit.Case, async: true

  alias Electric.Postgres.Lsn
  alias Electric.Postgres.ReplicationClient

  alias Electric.Replication.Changes.{
    DeletedRecord,
    NewRecord,
    Transaction,
    UpdatedRecord
  }

  @moduletag :capture_log
  @publication_name "test_electric_publication"
  @slot_name "test_electric_slot"

  describe "ReplicationClient init" do
    setup {Support.DbSetup, :with_unique_db}
    setup {Support.DbStructureSetup, :with_basic_tables}

    test "creates an empty publication on startup if requested", %{
      db_config: config,
      db_conn: conn
    } do
      replication_opts = [
        publication_name: @publication_name,
        try_creating_publication?: true,
        slot_name: @slot_name,
        transaction_received: nil
      ]

      assert {:ok, _} = ReplicationClient.start_link(config, replication_opts)

      assert %{rows: [[@publication_name]]} =
               Postgrex.query!(conn, "SELECT pubname FROM pg_publication", [])

      assert %{rows: []} = Postgrex.query!(conn, "SELECT pubname FROM pg_publication_tables", [])
    end
  end

  describe "ReplicationClient against real db" do
    setup [
      {Support.DbSetup, :with_unique_db},
      {Support.DbStructureSetup, :with_basic_tables},
      :setup_publication_and_replication_opts
    ]

    test "calls a provided function when receiving it from the PG",
         %{db_config: config, replication_opts: replication_opts, db_conn: conn} do
      assert {:ok, _pid} = ReplicationClient.start_link(config, replication_opts)

      {:ok, _} =
        Postgrex.query(conn, "INSERT INTO items (id, value) VALUES ($1, $2)", [
          Ecto.UUID.bingenerate(),
          "test value"
        ])

      assert_receive {:from_replication, %Transaction{changes: [change]}}
      assert %NewRecord{record: %{"value" => "test value"}} = change
    end

    test "logs a message when connected & replication has started",
         %{db_config: config, replication_opts: replication_opts, db_conn: conn} do
      log =
        ExUnit.CaptureLog.capture_log(fn ->
          assert {:ok, _pid} = ReplicationClient.start_link(config, replication_opts)

          {:ok, _} =
            Postgrex.query(conn, "INSERT INTO items (id, value) VALUES ($1, $2)", [
              Ecto.UUID.bingenerate(),
              "test value"
            ])

          assert_receive {:from_replication, %Transaction{changes: [change]}}
          assert %NewRecord{record: %{"value" => "test value"}} = change
        end)

      log =~ "Started replication from postgres"
    end

    test "works with an existing publication", %{
      db_config: config,
      replication_opts: replication_opts
    } do
      replication_opts = Keyword.put(replication_opts, :try_creating_publication?, true)
      assert {:ok, _} = ReplicationClient.start_link(config, replication_opts)
    end

    test "works with an existing replication slot", %{
      db_config: config,
      replication_opts: replication_opts,
      db_conn: conn
    } do
      {:ok, pid} = ReplicationClient.start_link(config, replication_opts)

      assert %{
               "slot_name" => @slot_name,
               "temporary" => false,
               "confirmed_flush_lsn" => flush_lsn
             } = fetch_slot_info(conn)

      # Check that the slot remains even when the replication client goes down
      true = Process.unlink(pid)
      true = Process.exit(pid, :kill)

      assert %{
               "slot_name" => @slot_name,
               "temporary" => false,
               "confirmed_flush_lsn" => ^flush_lsn
             } = fetch_slot_info(conn)

      # Check that the replication client works when the replication slot already exists
      {:ok, _pid} = ReplicationClient.start_link(config, replication_opts)

      assert %{
               "slot_name" => @slot_name,
               "temporary" => false,
               "confirmed_flush_lsn" => ^flush_lsn
             } = fetch_slot_info(conn)
    end

    @tag additional_fields:
           "date DATE, timestamptz TIMESTAMPTZ, float FLOAT8, bytea BYTEA, interval INTERVAL"
    test "returns data formatted according to display settings", %{
      db_config: config,
      replication_opts: replication_opts,
      db_conn: conn
    } do
      replication_opts = Keyword.put(replication_opts, :try_creating_publication?, true)
      db_name = Keyword.get(config, :database)

      # Set the DB's display settings to something else than Electric.Postgres.display_settings
      Postgrex.query!(conn, "ALTER DATABASE \"#{db_name}\" SET DateStyle='Postgres, DMY';", [])
      Postgrex.query!(conn, "ALTER DATABASE \"#{db_name}\" SET TimeZone='CET';", [])
      Postgrex.query!(conn, "ALTER DATABASE \"#{db_name}\" SET extra_float_digits=-1;", [])
      Postgrex.query!(conn, "ALTER DATABASE \"#{db_name}\" SET bytea_output='escape';", [])
      Postgrex.query!(conn, "ALTER DATABASE \"#{db_name}\" SET IntervalStyle='postgres';", [])

      assert {:ok, _} = ReplicationClient.start_link(config, replication_opts)

      {:ok, _} =
        Postgrex.query(
          conn,
          "INSERT INTO items (id, value, date, timestamptz, float, bytea, interval) VALUES ($1, $2, $3, $4, $5, $6, $7)",
          [
            Ecto.UUID.bingenerate(),
            "test value",
            ~D[2022-05-17],
            ~U[2022-01-12 00:01:00.00Z],
            1.234567890123456,
            # 5 in hex
            "0x5",
            %Postgrex.Interval{
              days: 1,
              months: 0,
              # 12 hours, 59 minutes, 10 seconds
              secs: 46750,
              microsecs: 0
            }
          ]
        )

      # Check that the incoming data is formatted according to Electric.Postgres.display_settings
      assert_receive {:from_replication, %Transaction{changes: [change]}}

      assert %NewRecord{
               record: %{
                 "date" => "2022-05-17",
                 "timestamptz" => timestamp,
                 "float" => "1.234567890123456",
                 "bytea" => "\\x307835",
                 "interval" => "P1DT12H59M10S"
               }
             } = change

      assert String.ends_with?(timestamp, "+00")
    end
  end

  describe "ReplicationClient against real db (toast)" do
    setup [
      {Support.DbSetup, :with_unique_db},
      {Support.DbStructureSetup, :with_basic_tables},
      :setup_publication_and_replication_opts
    ]

    setup %{db_config: config, replication_opts: replication_opts, db_conn: conn} do
      Postgrex.query!(
        conn,
        "CREATE TABLE items2 (id UUID PRIMARY KEY, val1 TEXT, val2 TEXT, num INTEGER)",
        []
      )

      Postgrex.query!(conn, "ALTER TABLE items2 REPLICA IDENTITY FULL", [])

      assert {:ok, _pid} = ReplicationClient.start_link(config, replication_opts)

      :ok
    end

    test "detoasts column values in deletes", %{db_conn: conn} do
      id = Ecto.UUID.generate()
      {:ok, bin_uuid} = Ecto.UUID.dump(id)
      long_string_1 = gen_random_string(2500)
      long_string_2 = gen_random_string(3000)

      Postgrex.query!(conn, "INSERT INTO items2 (id, val1, val2) VALUES ($1, $2, $3)", [
        bin_uuid,
        long_string_1,
        long_string_2
      ])

      assert_receive {:from_replication, %Transaction{changes: [change]}}

      assert %NewRecord{
               record: %{"id" => ^id, "val1" => ^long_string_1, "val2" => ^long_string_2},
               relation: {"public", "items2"}
             } = change

      Postgrex.query!(conn, "DELETE FROM items2 WHERE id = $1", [bin_uuid])

      assert_receive {:from_replication, %Transaction{changes: [change]}}

      assert %DeletedRecord{
               old_record: %{"id" => ^id, "val1" => ^long_string_1, "val2" => ^long_string_2},
               relation: {"public", "items2"}
             } = change
    end

    test "detoasts column values in updates", %{db_conn: conn} do
      id = Ecto.UUID.generate()
      {:ok, bin_uuid} = Ecto.UUID.dump(id)
      long_string_1 = gen_random_string(2500)
      long_string_2 = gen_random_string(3000)

      Postgrex.query!(conn, "INSERT INTO items2 (id, val1, val2) VALUES ($1, $2, $3)", [
        bin_uuid,
        long_string_1,
        long_string_2
      ])

      assert_receive {:from_replication, %Transaction{changes: [change]}}

      assert %NewRecord{
               record: %{"id" => ^id, "val1" => ^long_string_1, "val2" => ^long_string_2},
               relation: {"public", "items2"}
             } = change

      Postgrex.query!(conn, "UPDATE items2 SET num = 11 WHERE id = $1", [bin_uuid])

      assert_receive {:from_replication, %Transaction{changes: [change]}}

      assert %UpdatedRecord{
               record: %{
                 "id" => ^id,
                 "val1" => ^long_string_1,
                 "val2" => ^long_string_2,
                 "num" => "11"
               },
               changed_columns: changed_columns,
               relation: {"public", "items2"}
             } = change

      assert MapSet.new(["num"]) == changed_columns
    end
  end

  test "correctly responds to a status update request message from PG" do
    pg_wal = lsn_to_wal("0/10")

    state =
      ReplicationClient.State.new(
        transaction_received: nil,
        publication_name: "",
        try_creating_publication?: false,
        slot_name: ""
      )

    # Received WAL is PG WAL while "applied" and "flushed" WAL are still at zero based on the `state`.
    assert {:noreply, [<<?r, wal::64, 0::64, 0::64, _time::64, 0::8>>], state} =
             ReplicationClient.handle_data(<<?k, pg_wal::64, 0::64, 1::8>>, state)

    assert wal == pg_wal

    ###

    state = %{state | applied_wal: lsn_to_wal("0/10")}
    pg_wal = lsn_to_wal("1/20")

    assert {:noreply, [<<?r, wal::64, app_wal::64, app_wal::64, _time::64, 0::8>>], state} =
             ReplicationClient.handle_data(<<?k, pg_wal::64, 0::64, 1::8>>, state)

    assert wal == pg_wal
    assert app_wal == state.applied_wal
  end

  defp setup_publication_and_replication_opts(%{db_conn: conn}) do
    create_publication_for_all_tables(conn)

    %{
      replication_opts: [
        publication_name: @publication_name,
        try_creating_publication?: false,
        slot_name: @slot_name,
        transaction_received: {__MODULE__, :test_transaction_received, [self()]}
      ]
    }
  end

  def test_transaction_received(transaction, test_pid),
    do: send(test_pid, {:from_replication, transaction})

  defp create_publication_for_all_tables(conn),
    do: Postgrex.query!(conn, "CREATE PUBLICATION #{@publication_name} FOR ALL TABLES", [])

  defp gen_random_string(length) do
    Stream.repeatedly(fn -> :rand.uniform(125 - 32) + 32 end)
    |> Enum.take(length)
    |> List.to_string()
  end

  defp lsn_to_wal(lsn_str) when is_binary(lsn_str),
    do: lsn_str |> Lsn.from_string() |> Lsn.to_integer()

  defp fetch_slot_info(conn) do
    {:ok, result} = Postgrex.query(conn, "SELECT * FROM pg_replication_slots", [])
    assert %Postgrex.Result{columns: cols, rows: [row], num_rows: 1} = result

    Enum.zip(cols, row) |> Map.new()
  end
end
