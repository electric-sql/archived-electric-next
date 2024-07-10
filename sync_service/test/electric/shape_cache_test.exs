defmodule Electric.ShapeCacheTest do
  use ExUnit.Case, async: true
  import Support.ComponentSetup
  import Support.DbSetup
  import Support.DbStructureSetup

  alias Electric.ShapeCache.Storage
  alias Electric.ShapeCache
  alias Electric.Shapes.Shape
  alias Electric.Postgres.Lsn

  @moduletag :capture_log
  @basic_query_meta %Postgrex.Query{columns: ["id"], result_types: [:text], name: "key_prefix"}

  setup :with_in_memory_storage

  describe "get_or_create_shape_id/2" do
    setup(do: %{pool: :no_pool})

    setup(ctx,
      do:
        with_shape_cache(ctx,
          create_snapshot_fn: fn parent, shape_id, _, _, storage ->
            GenServer.cast(parent, {:snapshot_xmin_known, shape_id, 10})
            Storage.make_new_snapshot!(shape_id, @basic_query_meta, [["test"]], storage)
            GenServer.cast(parent, {:snapshot_ready, shape_id})
          end
        )
    )

    test "creates a new shape_id", %{shape_cache_opts: opts} do
      shape = %Shape{root_table: {"public", "items"}}
      {shape_id, 0} = ShapeCache.get_or_create_shape_id(shape, opts)
      assert is_binary(shape_id)
    end

    test "returns existing shape_id", %{shape_cache_opts: opts} do
      shape = %Shape{root_table: {"public", "items"}}
      {shape_id1, 0} = ShapeCache.get_or_create_shape_id(shape, opts)
      {shape_id2, 0} = ShapeCache.get_or_create_shape_id(shape, opts)
      assert shape_id1 == shape_id2
    end
  end

  describe "get_or_create_shape_id/2 shape initialization" do
    test "creates initial snapshot if one doesn't exist", %{storage: storage} = ctx do
      %{shape_cache_opts: opts} =
        with_shape_cache(Map.put(ctx, :pool, nil),
          create_snapshot_fn: fn parent, shape_id, _, _, storage ->
            GenServer.cast(parent, {:snapshot_xmin_known, shape_id, 10})
            Storage.make_new_snapshot!(shape_id, @basic_query_meta, [["test"]], storage)
            GenServer.cast(parent, {:snapshot_ready, shape_id})
          end
        )

      shape = %Shape{root_table: {"public", "items"}}
      {shape_id, offset} = ShapeCache.get_or_create_shape_id(shape, opts)
      assert offset == 0
      assert :ready = ShapeCache.wait_for_snapshot(opts[:server], shape_id, shape)
      assert Storage.snapshot_exists?(shape_id, storage)
    end

    test "triggers snapshot creation only once", ctx do
      test_pid = self()

      %{shape_cache_opts: opts} =
        with_shape_cache(Map.put(ctx, :pool, nil),
          create_snapshot_fn: fn parent, shape_id, _, _, storage ->
            send(test_pid, {:called, :create_snapshot_fn})
            GenServer.cast(parent, {:snapshot_xmin_known, shape_id, 10})
            Storage.make_new_snapshot!(shape_id, @basic_query_meta, [["test"]], storage)
            GenServer.cast(parent, {:snapshot_ready, shape_id})
          end
        )

      shape = %Shape{root_table: {"public", "items"}}
      {shape_id, _} = ShapeCache.get_or_create_shape_id(shape, opts)
      for _ <- 1..10, do: assert({^shape_id, _} = ShapeCache.get_or_create_shape_id(shape, opts))
      assert :ready = ShapeCache.wait_for_snapshot(opts[:server], shape_id, shape)

      assert_received {:called, :create_snapshot_fn}
      refute_received {:called, :create_snapshot_fn}
    end
  end

  describe "get_or_create_shape_id/2 against real db" do
    setup :with_unique_db
    setup :with_basic_tables
    setup :with_shape_cache

    setup %{pool: pool} do
      Postgrex.query!(pool, "INSERT INTO items (id, value) VALUES ($1, $2), ($3, $4)", [
        Ecto.UUID.dump!("721ae036-e620-43ee-a3ed-1aa3bb98e661"),
        "test1",
        Ecto.UUID.dump!("721ae036-e620-43ee-a3ed-1aa3bb98e662"),
        "test2"
      ])

      :ok
    end

    test "creates initial snapshot from DB data",
         %{storage: storage, shape_cache_opts: opts} do
      shape = %Shape{root_table: {"public", "items"}}
      {shape_id, _} = ShapeCache.get_or_create_shape_id(shape, opts)
      assert :ready = ShapeCache.wait_for_snapshot(opts[:server], shape_id, shape)
      assert Storage.snapshot_exists?(shape_id, storage)
      assert {0, stream} = Storage.get_snapshot(shape_id, storage)

      assert [%{value: %{"value" => "test1"}}, %{value: %{"value" => "test2"}}] =
               Enum.to_list(stream)
    end

    test "updates latest offset correctly",
         %{storage: storage, shape_cache_opts: opts} do
      shape = %Shape{root_table: {"public", "items"}}
      {shape_id, initial_offset} = ShapeCache.get_or_create_shape_id(shape, opts)
      assert :ready = ShapeCache.wait_for_snapshot(opts[:server], shape_id, shape)
      assert Storage.snapshot_exists?(shape_id, storage)
      assert {^shape_id, offset_after_snapshot} = ShapeCache.get_or_create_shape_id(shape, opts)

      expected_offset_after_log_entry = 1000
      :ok = ShapeCache.update_shape_latest_offset(shape_id, expected_offset_after_log_entry, opts)

      assert {^shape_id, offset_after_log_entry} = ShapeCache.get_or_create_shape_id(shape, opts)

      assert initial_offset == 0
      assert initial_offset == offset_after_snapshot
      assert offset_after_log_entry > offset_after_snapshot
      assert offset_after_log_entry == expected_offset_after_log_entry
    end

    test "fails to update latest offset if shape doesn't exist", %{shape_cache_opts: opts} do
      assert {:error, _} = ShapeCache.update_shape_latest_offset("foo", 10, opts)
    end

    test "correctly propagates the error", %{shape_cache_opts: opts} do
      shape = %Shape{root_table: {"public", "nonexistent"}}
      {shape_id, _} = ShapeCache.get_or_create_shape_id(shape, opts)

      assert {:error, %Postgrex.Error{postgres: %{code: :undefined_table}}} =
               ShapeCache.wait_for_snapshot(opts[:server], shape_id, shape)
    end
  end

  describe "list_active_shapes/1" do
    test "returns empty list initially", ctx do
      %{shape_cache_opts: opts} = with_shape_cache(Map.put(ctx, :pool, nil))
      assert ShapeCache.list_active_shapes(opts) == []
    end

    test "lists the shape as active once there is a snapshot", ctx do
      %{shape_cache_opts: opts} =
        with_shape_cache(Map.put(ctx, :pool, nil),
          create_snapshot_fn: fn parent, shape_id, _, _, storage ->
            GenServer.cast(parent, {:snapshot_xmin_known, shape_id, 10})
            Storage.make_new_snapshot!(shape_id, @basic_query_meta, [["test"]], storage)
            GenServer.cast(parent, {:snapshot_ready, shape_id})
          end
        )

      shape = %Shape{root_table: {"public", "items"}}
      {shape_id, _} = ShapeCache.get_or_create_shape_id(shape, opts)
      assert :ready = ShapeCache.wait_for_snapshot(opts[:server], shape_id, shape)
      assert [{^shape_id, ^shape, 10}] = ShapeCache.list_active_shapes(opts)
    end

    test "doesn't list the shape as active until we know xmin", ctx do
      test_pid = self()

      %{shape_cache_opts: opts} =
        with_shape_cache(Map.put(ctx, :pool, nil),
          create_snapshot_fn: fn parent, shape_id, _, _, storage ->
            ref = make_ref()
            send(test_pid, {:waiting_point, ref, self()})
            receive(do: ({:continue, ^ref} -> :ok))
            GenServer.cast(parent, {:snapshot_xmin_known, shape_id, 10})
            Storage.make_new_snapshot!(shape_id, @basic_query_meta, [["test"]], storage)
            GenServer.cast(parent, {:snapshot_ready, shape_id})
          end
        )

      shape = %Shape{root_table: {"public", "items"}}
      {shape_id, _} = ShapeCache.get_or_create_shape_id(shape, opts)

      # Wait until we get to the waiting point in the snapshot
      assert_receive {:waiting_point, ref, pid}

      assert ShapeCache.list_active_shapes(opts) == []

      send(pid, {:continue, ref})

      assert :ready = ShapeCache.wait_for_snapshot(opts[:server], shape_id, shape)
      assert [{^shape_id, ^shape, 10}] = ShapeCache.list_active_shapes(opts)
    end
  end

  describe "wait_for_snapshot/4" do
    test "returns :ready for existing snapshot", %{storage: storage} = ctx do
      %{shape_cache_opts: opts} = with_shape_cache(Map.put(ctx, :pool, nil))
      shape = %Shape{root_table: {"public", "items"}}
      {shape_id, _} = ShapeCache.get_or_create_shape_id(shape, opts)

      # Manually create a snapshot
      Storage.make_new_snapshot!(shape_id, @basic_query_meta, [["test"]], storage)

      assert ShapeCache.wait_for_snapshot(opts[:server], shape_id, shape) == :ready
    end

    test "creates a new snapshot if none were created for some reason",
         %{storage: storage} = ctx do
      shape_id = "orphaned_id"

      %{shape_cache_opts: opts} =
        with_shape_cache(Map.put(ctx, :pool, nil),
          create_snapshot_fn: fn parent, shape_id, _, _, storage ->
            GenServer.cast(parent, {:snapshot_xmin_known, shape_id, 10})
            Storage.make_new_snapshot!(shape_id, @basic_query_meta, [["test"]], storage)
            GenServer.cast(parent, {:snapshot_ready, shape_id})
          end
        )

      shape = %Shape{root_table: {"public", "items"}}

      assert :ready = ShapeCache.wait_for_snapshot(opts[:server], shape_id, shape)

      assert Storage.snapshot_exists?(shape_id, storage)
    end

    test "handles buffering multiple callers correctly", ctx do
      test_pid = self()

      %{shape_cache_opts: opts} =
        with_shape_cache(Map.put(ctx, :pool, nil),
          create_snapshot_fn: fn parent, shape_id, _, _, _storage ->
            ref = make_ref()
            send(test_pid, {:waiting_point, ref, self()})
            receive(do: ({:continue, ^ref} -> :ok))
            GenServer.cast(parent, {:snapshot_xmin_known, shape_id, 10})
            GenServer.cast(parent, {:snapshot_ready, shape_id})
          end
        )

      shape = %Shape{root_table: {"public", "items"}}
      {shape_id, _} = ShapeCache.get_or_create_shape_id(shape, opts)

      tasks =
        for _ <- 1..10,
            do: Task.async(ShapeCache, :wait_for_snapshot, [opts[:server], shape_id, shape])

      assert_receive {:waiting_point, ref, pid}
      send(pid, {:continue, ref})

      assert Enum.all?(Task.await_many(tasks), &(&1 == :ready))
    end

    test "propagates error in snapshot creation to listeners", ctx do
      test_pid = self()

      %{shape_cache_opts: opts} =
        with_shape_cache(Map.put(ctx, :pool, nil),
          create_snapshot_fn: fn parent, shape_id, _, _, _storage ->
            ref = make_ref()
            send(test_pid, {:waiting_point, ref, self()})
            receive(do: ({:continue, ^ref} -> :ok))
            GenServer.cast(parent, {:snapshot_xmin_known, shape_id, 10})

            GenServer.cast(
              parent,
              {:snapshot_failed, shape_id, %RuntimeError{message: "expected error"}, []}
            )
          end
        )

      shape = %Shape{root_table: {"public", "items"}}
      {shape_id, _} = ShapeCache.get_or_create_shape_id(shape, opts)

      assert_receive {:waiting_point, ref, pid}
      send(pid, {:continue, ref})

      assert {:error, %RuntimeError{message: "expected error"}} =
               ShapeCache.wait_for_snapshot(opts[:server], shape_id, shape)
    end
  end

  describe "handle_truncate/2" do
    test "cleans up shape data and rotates the shape id",
         %{storage: storage} = ctx do
      %{shape_cache_opts: opts} =
        with_shape_cache(Map.put(ctx, :pool, nil),
          create_snapshot_fn: fn parent, shape_id, _, _, storage ->
            GenServer.cast(parent, {:snapshot_xmin_known, shape_id, 10})
            Storage.make_new_snapshot!(shape_id, @basic_query_meta, [["test"]], storage)
            GenServer.cast(parent, {:snapshot_ready, shape_id})
          end
        )

      shape = %Shape{root_table: {"public", "items"}}
      {shape_id, _} = ShapeCache.get_or_create_shape_id(shape, opts)
      assert :ready = ShapeCache.wait_for_snapshot(opts[:server], shape_id, shape)

      Storage.append_to_log!(
        shape_id,
        Lsn.from_integer(1000),
        1,
        [
          %Electric.Replication.Changes.NewRecord{
            relation: {"public", "items"},
            record: %{"id" => "1", "name" => "Alice"}
          }
        ],
        storage
      )

      assert Storage.snapshot_exists?(shape_id, storage)
      assert Enum.count(Storage.get_log_stream(shape_id, 0, storage)) == 1

      ShapeCache.handle_truncate(opts[:server], shape_id)

      # Wait a bit for the async cleanup to complete
      Process.sleep(100)

      refute Storage.snapshot_exists?(shape_id, storage)
      assert Enum.count(Storage.get_log_stream(shape_id, 0, storage)) == 0
      {shape_id2, _} = ShapeCache.get_or_create_shape_id(shape, opts)
      assert shape_id != shape_id2
    end
  end

  describe "clean_shape/2" do
    test "cleans up shape data and rotates the shape id",
         %{storage: storage} = ctx do
      %{shape_cache_opts: opts} =
        with_shape_cache(Map.put(ctx, :pool, nil),
          create_snapshot_fn: fn parent, shape_id, _, _, storage ->
            GenServer.cast(parent, {:snapshot_xmin_known, shape_id, 10})
            Storage.make_new_snapshot!(shape_id, @basic_query_meta, [["test"]], storage)
            GenServer.cast(parent, {:snapshot_ready, shape_id})
          end
        )

      shape = %Shape{root_table: {"public", "items"}}
      {shape_id, _} = ShapeCache.get_or_create_shape_id(shape, opts)
      assert :ready = ShapeCache.wait_for_snapshot(opts[:server], shape_id, shape)

      Storage.append_to_log!(
        shape_id,
        Lsn.from_integer(1000),
        1,
        [
          %Electric.Replication.Changes.NewRecord{
            relation: {"public", "items"},
            record: %{"id" => "1", "name" => "Alice"}
          }
        ],
        storage
      )

      assert Storage.snapshot_exists?(shape_id, storage)
      assert Enum.count(Storage.get_log_stream(shape_id, 0, storage)) == 1

      ShapeCache.clean_shape(opts[:server], shape_id)

      # Wait a bit for the async cleanup to complete
      Process.sleep(100)

      refute Storage.snapshot_exists?(shape_id, storage)
      assert Enum.count(Storage.get_log_stream(shape_id, 0, storage)) == 0
      {shape_id2, _} = ShapeCache.get_or_create_shape_id(shape, opts)
      assert shape_id != shape_id2
    end
  end
end
