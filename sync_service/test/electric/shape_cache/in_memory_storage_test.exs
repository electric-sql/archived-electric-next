defmodule Electric.ShapeCache.InMemoryStorageTest do
  # TODO: Move these tests into the StorageImplimentationsTest
  use ExUnit.Case, async: true
  alias Electric.ShapeCache.InMemoryStorage
  alias Electric.Replication.Changes
  alias Electric.Postgres.Lsn

  setup %{test: test_id} do
    snapshot_table = :"snapshot_ets_table_#{test_id}"
    log_table = :"log_ets_table_#{test_id}"

    {:ok, opts} =
      InMemoryStorage.shared_opts(
        snapshot_ets_table: snapshot_table,
        log_ets_table: log_table
      )

    {:ok, pid} = InMemoryStorage.start_link(opts)
    %{opts: opts, pid: pid}
  end

  describe "get_latest_log_offset?/2" do
    test "returns 0 if only snapshot is available", %{opts: opts} do
      snapshot_ets_table = Map.fetch!(opts, :snapshot_ets_table)
      :ets.insert(snapshot_ets_table, {{"shape_id", 0}, %{"id" => "123", "name" => "Test"}})
      assert {:ok, 0} == InMemoryStorage.get_latest_log_offset("shape_id", opts)
    end

    test "returns latest offset for the given shape ID", %{opts: opts} do
      lsn1 = Lsn.from_integer(1000)
      lsn2 = Lsn.from_integer(2000)
      xid = 1

      changes1 = [
        %Changes.NewRecord{
          relation: {"public", "test_table"},
          record: %{"id" => "123", "name" => "Test A"}
        }
      ]

      changes2 = [
        %Changes.NewRecord{
          relation: {"public", "test_table"},
          record: %{"id" => "456", "name" => "Test B"}
        }
      ]

      :ok = InMemoryStorage.append_to_log!("shape_id", lsn1, xid, changes1, opts)
      :ok = InMemoryStorage.append_to_log!("shape_id", lsn2, xid, changes2, opts)
      assert {:ok, 2000} == InMemoryStorage.get_latest_log_offset("shape_id", opts)
    end

    test "returns error if shape does not exist", %{opts: opts} do
      assert :error == InMemoryStorage.get_latest_log_offset("shape_id", opts)
    end
  end

  describe "has_log_entry?/3" do
    test "should detect whether there is a snapshot when offset is 0", %{opts: opts} do
      refute InMemoryStorage.has_log_entry?("shape_id", 0, opts)

      snapshot_ets_table = Map.fetch!(opts, :snapshot_ets_table)
      :ets.insert(snapshot_ets_table, {{"shape_id", 0}, %{"id" => "123", "name" => "Test"}})
      assert InMemoryStorage.has_log_entry?("shape_id", 0, opts)
    end
  end
end
